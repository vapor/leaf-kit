/// Place all tests related to verifying that errors ARE thrown here

@testable import LeafKit
import NIOConcurrencyHelpers
import XCTest

final class LeafErrorTests: XCTestCase {

    /// Verify that cyclical references via #extend will throw `LeafError.cyclicalReference`
    func testCyclicalError() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        test.files["/c.leaf"] = "#extend(\"a\")"

        do {
            _ = try await TestRenderer(sources: .singleSource(test)).render(path: "a").get()
            XCTFail("Should have thrown LeafError.cyclicalReference")
        } catch let error as LeafError {
            switch error.reason {
            case .cyclicalReference(let name, let cycle):
                XCTAssertEqual([name: cycle], ["a": ["a","b","c","a"]])
            default:
                XCTFail("Wrong error: \(error.localizedDescription)")
            }
        } catch {
            XCTFail("Wrong error: \(error.localizedDescription)")
        }
    }
    
    /// Verify taht referecing a non-existent template will throw `LeafError.noTemplateExists`
    func testDependencyError() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"

        do {
            _ = try await TestRenderer(sources: .singleSource(test)).render(path: "a").get()
            XCTFail("Should have thrown LeafError.noTemplateExists")
        } catch let error as LeafError {
            switch error.reason {
            case .noTemplateExists(let name):
                XCTAssertEqual(name, "c")
            default:
                XCTFail("Wrong error: \(error.localizedDescription)")
            }
        } catch {
            XCTFail("Wrong error: \(error.localizedDescription)")
        }
    }
    
    /// Verify that rendering a template with a missing required parameter will throw `LeafError.missingParameter`
    func testMissingParameterError() async throws {
      var test = TestFiles()
      // Assuming "/missingParam.leaf" is a template that requires a parameter we intentionally don't provide
      test.files["/missingParam.leaf"] = """
          #(foo.bar.trim())
          """

        do {
            _ = try await TestRenderer(sources: .singleSource(test)).render(path: "missingParam", context: [:]).get()
            XCTFail("Should have thrown LeafError.unknownError")
        } catch let error as LeafError {
            switch error.reason {
            case .unknownError(let s):
                XCTAssertEqual(s, "Found nil while iterating through params")
            default:
                XCTFail("Expected LeafError.unknownError(\"Found nil while iterating through params\"), got \(String(reflecting: error))")
            }
        } catch {
            XCTFail("Expected LeafError.unknownError(\"Found nil while iterating through params\"), got \(String(reflecting: error))")
        }
    }
}
