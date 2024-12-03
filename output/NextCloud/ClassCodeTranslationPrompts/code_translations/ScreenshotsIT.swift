
import XCTest

class ScreenshotsIT: XCTestCase {
    override class func setUp() {
        super.setUp()
        Screengrab.setDefaultScreenshotStrategy(UiAutomatorScreenshotStrategy())
    }
    
    func gridViewScreenshot() {
        let app = XCUIApplication()
        app.launch()
        
        let gridViewButton = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Switch to Grid View", "switch_grid_view_button")).firstMatch
        gridViewButton.tap()
        
        sleep(1)
        
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "01_gridView"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        let listViewButton = app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Switch to List View", "switch_grid_view_button")).firstMatch
        listViewButton.tap()
        
        XCTAssertTrue(true) // if we reach this, everything is ok
    }
    
    func listViewScreenshot() {
        let path = "/Camera/"
        
        // folder does not exist yet
        if getStorageManager().getFileByEncryptedRemotePath(path) == nil {
            let syncOp = CreateFolderOperation(path: path, user: user, targetContext: targetContext, storageManager: getStorageManager())
            let result = syncOp.execute(client: client)
            
            XCTAssertTrue(result.isSuccess)
        }
        
        let scenario = FileDisplayActivity.launch()
        
        // go into work folder
        onView(withId: R.id.list_root).perform(RecyclerViewActions.actionOnItemAtPosition(0, click()))
        
        Screengrab.screenshot("02_listView")
        
        XCTAssertTrue(true) // if we reach this, everything is ok
    }
    
    func drawerScreenshot() {
        let app = XCUIApplication()
        app.launch()
        
        let drawer = app.otherElements["drawer_layout"]
        drawer.swipeRight()
        
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "03_drawer"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        drawer.swipeLeft()
        
        XCTAssertTrue(true) // if we reach this, everything is ok
    }
    
    func multipleAccountsScreenshot() {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["switch_account_button"].tap()
        
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "04_accounts"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        app.navigationBars.buttons.element(boundBy: 0).tap()
        
        XCTAssertTrue(true) // if we reach this, everything is ok
    }
    
    func testAutoUploadScreenshot() {
        let app = XCUIApplication()
        app.launch()
        
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "05_autoUpload"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        XCTAssertTrue(true) // if we reach this, everything is ok
    }
    
    func davdroidScreenshot() {
        let app = XCUIApplication()
        app.launch()
        
        let moreCell = app.tables.staticTexts["More"]
        moreCell.scrollToElement()
        
        shortSleep()
        
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "06_davdroid"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        XCTAssertTrue(true) // if we reach this, everything is ok
    }
}
