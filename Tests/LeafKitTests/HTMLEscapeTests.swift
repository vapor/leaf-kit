@testable import LeafKit
import XCTest

final class HTMLEscapeTests: XCTestCase {
    func testCorrectness() {
        XCTAssertEqual("".htmlEscaped(), "")
        XCTAssertEqual("abcdef".htmlEscaped(), "abcdef")
        XCTAssertEqual("abc&<>\"'".htmlEscaped(), "abc&amp;&lt;&gt;&quot;&#39;")
        XCTAssertEqual("abc&".htmlEscaped(), "abc&amp;")
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
