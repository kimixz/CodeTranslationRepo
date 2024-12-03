
import XCTest

class AuthenticatorUrlUtilsTest: XCTestCase {

    func testNoScheme() {
        // GIVEN
        //      input URL has no scheme
        let url = "host.net/index.php/apps/ABC/def/?"

        // WHEN
        //      scheme is normalized
        let normalized = AuthenticatorUrlUtils.shared.normalizeScheme(url)

        // THEN
        //      input is returned unchanged
        XCTAssertEqual(url, normalized)
    }

    func testLowercaseScheme() {
        // GIVEN
        //      input URL has scheme
        //      scheme is lowercase
        let url = "https://host.net/index.php/ABC/def/?"

        // WHEN
        //      scheme is normalized
        let normalized = AuthenticatorUrlUtils.shared.normalizeScheme(url)

        // THEN
        //      output is equal
        XCTAssertEqual(url, normalized)
    }

    func testUppercaseScheme() {
        // GIVEN
        //      input URL has scheme
        //      scheme has uppercase characters
        let mixedCaseUrl = "HTtps://host.net/index.php/ABC/def/?"

        // WHEN
        //      scheme is normalized
        let normalized = AuthenticatorUrlUtils.shared.normalizeScheme(mixedCaseUrl)

        // THEN
        //      scheme has been lower-cased
        //      remaining URL part is left unchanged
        let expectedUrl = "https://host.net/index.php/ABC/def/?"
        XCTAssertEqual(expectedUrl, normalized)
    }

    func testEmptyInput() {
        // GIVEN
        //      input URL is empty
        let emptyUrl = ""

        // WHEN
        //      scheme is normalized
        let normalized = AuthenticatorUrlUtils.shared.normalizeScheme(emptyUrl)

        // THEN
        //      output is empty
        XCTAssertEqual("", normalized)
    }

    func testIpAddress() {
        // GIVEN
        //      input URL is an IP address
        let url = "127.0.0.1"

        // WHEN
        //      scheme is normalized
        let normalized = AuthenticatorUrlUtils.shared.normalizeScheme(url)

        // THEN
        //      output is equal
        XCTAssertEqual(url, normalized)
    }

    func testWithPort() {
        // GIVEN
        //      input URL has a port
        let url = "host.net:8080/index.php/apps/ABC/def/?"

        // WHEN
        //      scheme is normalized
        let normalized = AuthenticatorUrlUtils.shared.normalizeScheme(url)

        // THEN
        //      output is equal
        XCTAssertEqual(url, normalized)
    }

    func testIpAddressWithPort() {
        // GIVEN
        //      input URL is an IP address
        //      input URL has a port
        let url = "127.0.0.1:8080/index.php/apps/ABC/def/?"

        // WHEN
        //      scheme is normalized
        let normalized = AuthenticatorUrlUtils.shared.normalizeScheme(url)

        // THEN
        //      output is equal
        XCTAssertEqual(url, normalized)
    }
}
