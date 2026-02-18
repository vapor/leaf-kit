@testable import LeafKit
import XCTest

final class HTMLEscapeTests: XCTestCase {
    func testCorrectness() {
        XCTAssertEqual("".htmlEscaped(), "")
        XCTAssertEqual("abcdef".htmlEscaped(), "abcdef")
        XCTAssertEqual("abc&<>\"'".htmlEscaped(), "abc&amp;&lt;&gt;&quot;&#39;")
        XCTAssertEqual("abc&".htmlEscaped(), "abc&amp;")
    }

    func testExtendedGraphemeClusterBypass() {
        let quoteWithCombining = "\u{0022}\u{0301}"  // "́
        let escaped = quoteWithCombining.htmlEscaped()

        XCTAssertEqual(escaped, "&quot;\u{0301}")

        let maliciousInput = "\"\u{0301}=1 autofocus tabindex=0 onfocus=alert(1)"
        let escapedMalicious = maliciousInput.htmlEscaped()

        XCTAssertFalse(escapedMalicious.contains("\"\u{0301}"))
        XCTAssertTrue(escapedMalicious.unicodeScalars.starts(with: "&quot;".unicodeScalars))

        let ampersandWithCombining = "&\u{0301}"  // &́
        XCTAssertEqual(ampersandWithCombining.htmlEscaped(), "&amp;\u{0301}")

        let lessThanWithCombining = "<\u{0301}"  // <́
        XCTAssertEqual(lessThanWithCombining.htmlEscaped(), "&lt;\u{0301}")

        let greaterThanWithCombining = ">\u{0301}"  // >́
        XCTAssertEqual(greaterThanWithCombining.htmlEscaped(), "&gt;\u{0301}")

        let apostropheWithCombining = "'\u{0301}"  // '́
        XCTAssertEqual(apostropheWithCombining.htmlEscaped(), "&#39;\u{0301}")
    }

    #if !os(Android)
    func testShortStringNoReplacements() {
        let string = "abcde12345"
        measure {
            _ = string.htmlEscaped()
        }
    }

    func testShortStringWithReplacements() {
        // The result should still fit into 15 bytes to hit the in-place String storage optimization.
        let string = "<abcdef>"
        measure {
            _ = string.htmlEscaped()
        }
    }

    static let mediumStringNoReplacements: String = {
        let lowercase = Array(UInt8(ascii: "a")...UInt8(ascii: "z"))
        let digits = Array(UInt8(ascii: "0")...UInt8(ascii: "9"))
        let uppercase = Array(UInt8(ascii: "A")...UInt8(ascii: "Z"))

        return String(bytes: lowercase + digits + uppercase, encoding: .utf8)!
    }()

    func testMediumStringNoReplacements() {
        measure {
            _ = HTMLEscapeTests.mediumStringNoReplacements.htmlEscaped()
        }
    }

    static let mediumStringWithReplacements: String = {
        let lowercase = Array(UInt8(ascii: "a")...UInt8(ascii: "z"))
        let digits = Array(UInt8(ascii: "0")...UInt8(ascii: "9"))
        let uppercase = Array(UInt8(ascii: "A")...UInt8(ascii: "Z"))
        let allCharacters = [[UInt8(ascii: "&")], lowercase, [UInt8(ascii: "\"")], digits, [UInt8(ascii: "'")], uppercase, [UInt8(ascii: "<")], [UInt8(ascii: ">")]]
            .flatMap { $0 }

        return String(bytes: allCharacters, encoding: .utf8)!
    }()

    func testMediumStringWithReplacements() {
        measure {
            _ = HTMLEscapeTests.mediumStringWithReplacements.htmlEscaped()
        }
    }

    func testMediumStringWithOnlyReplacements() {
        let string = Array(repeating: "&<>\"'", count: 10).joined(separator: "")
        measure {
            _ = string.htmlEscaped()
        }
    }

    func testLongStringNoReplacements() {
        let longString = Array(repeating: HTMLEscapeTests.mediumStringNoReplacements, count: 20).joined(separator: "")
        measure {
            _ = longString.htmlEscaped()
        }
    }

    func testLongStringWithReplacements() {
        let longString = Array(repeating: HTMLEscapeTests.mediumStringWithReplacements, count: 20).joined(separator: "")
        measure {
            _ = longString.htmlEscaped()
        }
    }
    #endif
}
