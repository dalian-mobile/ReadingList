import Foundation
import CloudKit
import CoreData
import Logging
import Combine
import UIKit
import Reachability

final class SyncCoordinator {

    private let persistentContainer: NSPersistentContainer
    let typesToSync: [CKRecordRepresentable.Type]
    let downstreamProcessor: DownstreamSyncProcessor
    let upstreamProcessor: UpstreamSyncProcessor
    private(set) var disabledReason: SyncDisabledReason?
    private(set) var isStarted = false

    init(persistentContainer: NSPersistentContainer, orderedTypesToSync: [CKRecordRepresentable.Type]) {
        self.persistentContainer = persistentContainer
        typesToSync = orderedTypesToSync
        syncContext = Self.buildSyncContext(storeCoordinator: persistentContainer.persistentStoreCoordinator)
        downstreamProcessor = DownstreamSyncProcessor(syncContext: syncContext, types: orderedTypesToSync, cloudOperationQueue: cloudOperationQueue)
        upstreamProcessor = UpstreamSyncProcessor(container: persistentContainer, syncContext: syncContext, cloudOperationQueue: cloudOperationQueue, types: orderedTypesToSync)

        downstreamProcessor.coordinator = self
        upstreamProcessor.coordinator = self
        cloudKitInitialiser.coordinator = self
    }

    private let syncContext: NSManagedObjectContext
    private let cloudOperationQueue = ConcurrentCKQueue()
    private lazy var cloudKitInitialiser = CloudKitInitialiser(cloudOperationQueue: cloudOperationQueue)
    private var cancellables = Set<AnyCancellable>()

    private lazy var reachability: Reachability? = {
        do {
            return try Reachability()
        } catch {
            logger.error("Reachability could not be initialized: \(error.localizedDescription)")
            return nil
        }
    }()

    private static func buildSyncContext(storeCoordinator: NSPersistentStoreCoordinator) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = storeCoordinator
        context.name = "SyncEngineContext"
        try! context.setQueryGenerationFrom(.current)
        // Ensure that other changes made to the store trump the changes made in this context, so that UI changes don't get overwritten
        // by sync chnages.
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    func start() {
        if isStarted {
            logger.error("SyncCoordinator asked to start but has already started")
            return
        }
        logger.info("SyncCoordinator starting")
        self.disabledReason = nil
        self.cloudOperationQueue.resume()
        self.cloudKitInitialiser.prepareCloudEnvironment { [unowned self] in
            logger.info("Cloud environment prepared")

            self.downstreamProcessor.enqueueFetchRemoteChanges()
            self.upstreamProcessor.start()

            NotificationCenter.default.publisher(for: .CKAccountChanged)
                .sink { [unowned self] _ in
                    logger.info("CKAccountChanged; verifying user record ID")
                    if self.cloudOperationQueue.operationQueue.isSuspended {
                        self.cloudOperationQueue.resume()
                    }
                    self.cloudKitInitialiser.verifyUserRecordID()
                }.store(in: &self.cancellables)

            // Monitoring the network reachabiity will allow us to automatically re-do work when network connectivity resumes
            self.startNetworkMonitoring()
            NotificationCenter.default.publisher(for: .reachabilityChanged)
                .sink(receiveValue: self.networkConnectivityDidChange)
                .store(in: &self.cancellables)

            isStarted = true
        }
    }

    func transactionsPendingUpload() -> [NSPersistentHistoryTransaction] {
        upstreamProcessor.localTransactionsPendingPushCompletion
    }

    func stop() {
        logger.info("Stopping sync coordinator")
        cancellables.forEach {
            $0.cancel()
        }
        cancellables.removeAll()
        upstreamProcessor.stop()

        cloudOperationQueue.suspend()
        cloudOperationQueue.cancelAll()
        isStarted = false
    }
    
    func reset() {
        upstreamProcessor.reset()
        downstreamProcessor.resetChangeTracking()
    }

    var isRunning: Bool {
        !cloudOperationQueue.operationQueue.isSuspended
    }

    func disableSync(reason: SyncDisabledReason) {
        stop()
        CloudSyncSettings.settings.syncEnabled = false
        disabledReason = reason
    }

    func stopSyncDueToError(_ error: SyncCoordinatorError) {
        logger.critical("Stopping SyncCoordinator due to unexpected response")
        UserEngagement.logError(error)
        disabledReason = .unexpectedError
        stop()
    }

    func disableSyncDueOutOfDateLocalAppVersion() {
        logger.error("Stopping SyncCoordinator because the server contains data which is from a newer version of the app")
        stop()
        disabledReason = .outOfDateApp
        // TODO Consider caching this info and erasing upon upgrade, so we don't keep attempting to get data on every startup (maybe it doesn't matter)
    }

    func forceFullResync() {
        cloudOperationQueue.cancelAll()
        cloudOperationQueue.addBlock {
            self.syncContext.performAndWait {
                self.eraseSyncMetadata()

                self.downstreamProcessor.resetChangeTracking()
                self.downstreamProcessor.enqueueFetchRemoteChanges()

                self.upstreamProcessor.enqueueUploadOperations()
            }
        }
    }

    func eraseSyncMetadata() {
        let syncHelper = SyncResetter(managedObjectContext: self.syncContext, entityTypes: self.typesToSync.map { $0.entity(in: syncContext) })
        syncHelper.eraseSyncMetadata()
    }

    func enqueueFetchRemoteChanges(completion: ((UIBackgroundFetchResult) -> Void)? = nil) {
        self.downstreamProcessor.enqueueFetchRemoteChanges(completion: completion)
    }

    func requestFetch(for recordIDs: [CKRecord.ID]) {
        self.downstreamProcessor.fetchRecords(recordIDs)
    }

    func status() -> SyncStatus {
        var totalCounts = [String: Int]()
        var uploadedCounts = [String: Int]()
        syncContext.performAndWait {
            for type in typesToSync {
                let fetchRequest = type.fetchRequest(in: syncContext)
                let countResult = try! syncContext.count(for: fetchRequest)
                totalCounts[type.ckRecordType] = countResult

                fetchRequest.predicate = NSPredicate(format: "ckRecordEncodedSystemFields != nil")
                let uploadedCount = try! syncContext.count(for: fetchRequest)
                uploadedCounts[type.ckRecordType] = uploadedCount
            }
        }

        return SyncStatus(
            objectCountByEntityName: totalCounts,
            uploadedObjectCount: uploadedCounts,
            lastProcessedLocalTransaction: upstreamProcessor.latestConfirmedUploadedTransaction
        )
    }

    // MARK: - Network Monitoring
    private func startNetworkMonitoring() {
        guard let reachability = reachability else { return }
        do {
            try reachability.startNotifier()
        } catch {
            logger.error("Error starting reachability notifier: \(error.localizedDescription)")
        }
    }

    private func networkConnectivityDidChange(_ notification: Notification) {
        guard let reachability = self.reachability else { preconditionFailure("Reachability was nil in a networkChange callback") }
        logger.debug("Network connectivity changed to \(reachability.connection.description)")
        if reachability.connection == .unavailable {
            logger.info("Suspending operation queue due to lack of network connectivity")
            self.cloudOperationQueue.suspend()
        } else {
            logger.info("Resuming operation queue due to available network connectivity")
            self.cloudOperationQueue.resume()
            self.downstreamProcessor.enqueueFetchRemoteChanges()
        }
    }
}