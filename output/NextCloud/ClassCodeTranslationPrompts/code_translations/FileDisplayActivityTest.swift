
import XCTest

class FileDisplayActivityTest: XCTestCase {
    func testSetupToolbar() {
        let expectation = XCTestExpectation(description: "Wait for activity to be recreated")
        
        let scenario = XCUIApplication()
        scenario.launch()
        
        DispatchQueue.main.async {
            let activity = XCUIApplication().windows.element(boundBy: 0)
            if activity.identifier == "WhatsNewActivity" {
                activity.buttons["Back"].tap()
            }
        }
        
        scenario.terminate()
        scenario.launch()
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 5.0)
    }
}
