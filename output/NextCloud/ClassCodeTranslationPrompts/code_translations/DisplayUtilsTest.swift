
import XCTest

class DisplayUtilsTest: XCTestCase {
    func testConvertIdn() {
        XCTAssertEqual("", DisplayUtils.convertIdn("", true))
        XCTAssertEqual("", DisplayUtils.convertIdn("", false))
        XCTAssertEqual("http://www.nextcloud.com", DisplayUtils.convertIdn("http://www.nextcloud.com", true))
        XCTAssertEqual("http://www.xn--wlkchen-90a.com", DisplayUtils.convertIdn("http://www.wölkchen.com", true))
        XCTAssertEqual("http://www.wölkchen.com", DisplayUtils.convertIdn("http://www.xn--wlkchen-90a.com", false))
    }
}
