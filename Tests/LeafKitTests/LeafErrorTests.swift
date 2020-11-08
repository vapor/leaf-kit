/// Place all tests related to verifying that errors ARE thrown here

import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class LeafErrorTests: XCTestCase {

    /// Verify that cyclical references via #extend will throw `LeafError.cyclicalReference`
    func testCyclicalError() {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        test.files["/c.leaf"] = "#extend(\"a\")"

        do {
            _ = try TestRenderer(sources: .singleSource(test)).render(path: "a").wait()
            XCTFail("Should have thrown LeafError.cyclicalReference")
        } catch let error as LeafError {
            switch error.reason {
                case .cyclicalReference(let name, let cycle):
                    XCTAssertEqual([name: cycle], ["a": ["a","b","c","a"]])
                default: XCTFail("Wrong error: \(error.localizedDescription)")
            }
        } catch {
            XCTFail("Wrong error: \(error.localizedDescription)")
        }
    }
    
    /// Verify taht referecing a non-existent template will throw `LeafError.noTemplateExists`
    func testDependencyError() {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"

        do {
            _ = try TestRenderer(sources: .singleSource(test)).render(path: "a").wait()
            XCTFail("Should have thrown LeafError.noTemplateExists")
        } catch let error as LeafError {
            switch error.reason {
                case .noTemplateExists(let name): XCTAssertEqual(name,"c")
                default: XCTFail("Wrong error: \(error.localizedDescription)")
            }
        } catch {
            XCTFail("Wrong error: \(error.localizedDescription)")
        }
    }
}
