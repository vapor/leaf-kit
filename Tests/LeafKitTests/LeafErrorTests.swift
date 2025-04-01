/// Place all tests related to verifying that errors ARE thrown here.

@testable import LeafKit
import XCTest

final class LeafErrorTests: XCTestCase {
    /// Verify that cyclical references via #extend will throw `LeafError.cyclicalReference`
    func testCyclicalError() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        test.files["/c.leaf"] = "#extend(\"a\")"

        await XCTAssertThrowsErrorAsync(try await TestRenderer(sources: .singleSource(test)).render(path: "a")) {
            switch ($0 as? LeafError)?.reason {
            case .cyclicalReference(let name, let cycle):
                XCTAssertEqual(name, "a")
                XCTAssertEqual(cycle, ["a", "b", "c", "a"])
            default:
                XCTFail("Expected .cyclicalReference(a, [a, b, c, a]), got \($0.localizedDescription)")
            }
        }
    }
    
    /// Verify that referencing a non-existent template will throw `LeafError.noTemplateExists`
    func testDependencyError() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"

        await XCTAssertThrowsErrorAsync(try await TestRenderer(sources: .singleSource(test)).render(path: "a")) {
            switch ($0 as? LeafError)?.reason {
            case .noTemplateExists(let name):
                XCTAssertEqual(name, "c")
            default:
                XCTFail("Expected .noTemplateExists(c), got \($0.localizedDescription)")
            }
        }
    }
    
    /// Verify that rendering a template with a missing required parameter will throw `LeafError.missingParameter`
    func testMissingParameterError() async throws {
      var test = TestFiles()
      // Assuming "/missingParam.leaf" is a template that requires a parameter we intentionally don't provide
      test.files["/missingParam.leaf"] = """
          #(foo.bar.trim())
          """

        await XCTAssertThrowsErrorAsync(try await TestRenderer(sources: .singleSource(test)).render(path: "missingParam", context: [:])) {
            switch ($0 as? LeafError)?.reason {
            case .unknownError(let s):
                XCTAssertEqual(s, "Found nil while iterating through params")
            default:
                XCTFail("Expected .unknownError(Found nil while iterating through params), got \($0.localizedDescription)")
            }
        }
    }
}
