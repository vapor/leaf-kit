/// Place all tests related to verifying that errors ARE thrown here

import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class LeafErrorTests: LeafTestClass {
    /// Verify that cyclical references via #extend will throw `LeafError.cyclicalReference`
    func testCyclicalError() {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        test.files["/c.leaf"] = "#extend(\"a\")"
        let expected = "a cyclically referenced in [a -> b -> c -> !a]"

        do { _ = try TestRenderer(sources: .singleSource(test)).render(path: "a").wait()
             XCTFail("Should have thrown LeafError.cyclicalReference") }
        catch let error as LeafError { XCTAssert(error.localizedDescription.contains(expected)) }
        catch { XCTFail("Should have thrown LeafError.cyclicalReference") }
    }
    
    /// Verify that referecing a non-existent template will throw `LeafError.noTemplateExists`
    func testDependencyError() {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        let expected = "No template found for c"

        do { _ = try TestRenderer(sources: .singleSource(test)).render(path: "a").wait()
             XCTFail("Should have thrown LeafError.noTemplateExists") }
        catch let error as LeafError { XCTAssert(error.localizedDescription.contains(expected)) }
        catch { XCTFail("Should have thrown LeafError.noTemplateExists") }
    }
}
