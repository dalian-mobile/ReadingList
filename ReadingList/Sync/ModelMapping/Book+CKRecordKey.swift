import Foundation
import CoreData
import CloudKit

extension Book {
    /**
     Encapsulates the mapping between Book objects and CKRecord values
     */
    enum CKRecordKey: String, CaseIterable { //swiftlint:disable redundant_string_enum_value
        // REMEMBER to update the record schema version if we adjust this mapping
        case title = "title"
        case subtitle = "subtitle"
        case authors = "authors"
        case googleBooksId = "googleBooksId"
        case manualBookId = "manualBookId"
        case isbn13 = "isbn13"
        case pageCount = "pageCount"
        case publicationDate = "publicationDate"
        case bookDescription = "bookDescription"
        case coverImage = "coverImage"
        case notes = "notes"
        case currentPage = "currentPage"
        case languageCode = "languageCode"
        case rating = "rating"
        case sort = "sort"
        case readDates = "readDates" //swiftlint:enable redundant_string_enum_value

        static func from(coreDataKey: String) -> CKRecordKey? { //swiftlint:disable:this cyclomatic_complexity
            switch coreDataKey {
            case #keyPath(Book.title): return .title
            case #keyPath(Book.subtitle): return .subtitle
            case #keyPath(Book.authors): return .authors
            case #keyPath(Book.coverImage): return .coverImage
            case #keyPath(Book.googleBooksId): return .googleBooksId
            case #keyPath(Book.manualBookId): return .manualBookId
            case Book.Key.isbn13.rawValue: return .isbn13
            case Book.Key.pageCount.rawValue: return .pageCount
            case #keyPath(Book.publicationDate): return .publicationDate
            case #keyPath(Book.bookDescription): return .bookDescription
            case #keyPath(Book.notes): return .notes
            case Book.Key.currentPage.rawValue: return .currentPage
            case Book.Key.languageCode.rawValue: return .languageCode
            case Book.Key.rating.rawValue: return .rating
            case #keyPath(Book.sort): return .sort
            case #keyPath(Book.startedReading): return .readDates
            case #keyPath(Book.finishedReading): return .readDates
            default: return nil
            }
        }
    }
}