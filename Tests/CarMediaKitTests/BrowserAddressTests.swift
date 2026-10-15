import Foundation
import XCTest
@testable import CarMediaKit

final class BrowserAddressTests: XCTestCase {
    private let template = "https://search.example.com/?q=%@"

    private func address(_ input: String) -> URL? {
        BrowserAddress.url(for: input, searchTemplate: template)
    }

    func testFullURLIsKept() {
        XCTAssertEqual(address("https://www.example.com/a/b?c=1")?.absoluteString, "https://www.example.com/a/b?c=1")
        XCTAssertEqual(address("http://example.com")?.absoluteString, "http://example.com")
    }

    func testHostGetsHTTPS() {
        XCTAssertEqual(address("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(address("  example.com \n")?.absoluteString, "https://example.com", "input is trimmed")
        XCTAssertEqual(address("news.example.com/a?b=1")?.absoluteString, "https://news.example.com/a?b=1")
        XCTAssertEqual(address("sub.example.com:8080")?.absoluteString, "https://sub.example.com:8080")
    }

    func testTextBecomesSearch() {
        XCTAssertEqual(address("two words")?.absoluteString, "https://search.example.com/?q=two%20words")
        XCTAssertEqual(address("example")?.absoluteString, "https://search.example.com/?q=example", "no dot is not a host")
        XCTAssertEqual(address("example.c")?.host, "search.example.com", "one-letter TLD is not a host")
        XCTAssertEqual(address("user@example.com")?.host, "search.example.com", "an email is not a host")
    }

    func testQueryIsEncodedSafely() {
        XCTAssertEqual(address("a&b=c")?.absoluteString, "https://search.example.com/?q=a%26b%3Dc")
        XCTAssertEqual(address("1+1?")?.absoluteString, "https://search.example.com/?q=1%2B1%3F")
    }

    func testNeverReturnsNonWebScheme() {
        for input in ["javascript:alert(1)", "file:///etc/hosts", "ftp://example.com", "data:text/html,hi",
                      "carmedya://open", "mailto:a@example.com"] {
            let url = address(input)
            XCTAssertNotNil(url, input)
            XCTAssertEqual(url?.scheme, "https", input)
            XCTAssertEqual(url?.host, "search.example.com", "\(input) becomes a search")
        }
    }

    func testEmptyInputIsNil() {
        XCTAssertNil(address(""))
        XCTAssertNil(address("   "))
        XCTAssertNil(address("\n\t"))
    }
}
