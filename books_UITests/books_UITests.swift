//
//  books_UITests.swift
//  books_UITests
//
//  Created by Andrew Bennet on 25/10/2016.
//  Copyright © 2016 Andrew Bennet. All rights reserved.
//

import XCTest

class ReadingListApplication : XCUIApplication {
    enum tab : Int {
        case toRead = 0
        case finished = 1
        case settings = 2
    }
    
    enum addMethod : Int {
        case searchOnline = 1
        case enterManually = 2
    }
    
    var testDataAdded = false
    
    func clickTab(_ tab: tab) {
        tabBars.buttons.element(boundBy: UInt(tab.rawValue)).tap()
    }
    
    func addTestDataIfNotAdded() {
        guard testDataAdded == false else { return }
        
        clickTab(.settings)
        tables.cells.staticTexts["Use Test Data"].tap()
        testDataAdded = true
    }
    
    func clickAddButton(addMethod: addMethod) {
        navigationBars.element(boundBy: 0).buttons["Add"].tap()
        sheets.buttons.element(boundBy: UInt(addMethod.rawValue)).tap()
    }
    
    var topNavBar: XCUIElement {
        get {
            return navigationBars.element(boundBy: UInt(navigationBars.count - 1))
        }
    }
}

class books_UITests: XCTestCase {
        
    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        let app = ReadingListApplication()
        app.launch()

        // Add some test data
        app.addTestDataIfNotAdded()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testAddManualBook() {
        let app = ReadingListApplication()
        
        app.clickTab(.toRead)
        
        let initialNumberOfCells = Int(app.tables.cells.count)
        app.clickAddButton(addMethod: .enterManually)
        
        // Add some book metadata
        app.textFields.element(boundBy: 0).tap()
        app.typeText("The Catcher in the Rye")
        app.textFields.element(boundBy: 1).tap()
        app.typeText("J. D. Salinger")
        
        app.topNavBar.buttons["Next"].tap()
        app.topNavBar.buttons["Done"].tap()
        
        sleep(1)
        XCTAssertEqual(app.tables.cells.count, UInt(initialNumberOfCells + 1))
    }
    
    func testEditBook() {
        let app = ReadingListApplication()
        
        app.clickTab(.toRead)
        app.tables.cells.element(boundBy: 0).tap()
        app.topNavBar.buttons["Edit"].tap()
        
        app.textFields.element(boundBy: 0).tap()
        app.typeText("changed!")
        app.topNavBar.buttons["Done"].tap()
    }
    
    func testDeleteBook() {
        let app = ReadingListApplication()
        
        app.clickTab(.toRead)
        let bookCount = Int(app.tables.cells.count)
        
        app.tables.cells.element(boundBy: 0).tap()
        app.topNavBar.buttons["Edit"].tap()
        
        app.tables.staticTexts["Delete Book"].tap()
        app.sheets.buttons["Delete"].tap()
        
        sleep(1)
        XCTAssertEqual(app.tables.cells.count, UInt(bookCount - 1))
    }
}
