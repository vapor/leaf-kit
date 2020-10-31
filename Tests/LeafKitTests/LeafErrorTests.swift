/// Place all tests related to verifying that errors ARE thrown here
@testable import XCTLeafKit

final class LeafErrorTests: MemoryRendererTestCase {
    /// Verify that cyclical references via #extend will throw `LeafError.cyclicalReference`
    func testCyclicalError() {
        files["/a.leaf"] = "#inline(\"b\")"
        files["/b.leaf"] = "#inline(\"c\")"
        files["/c.leaf"] = "#inline(\"a\")"
        
        try AssertErrors(render("a"),
                         contains: "`a` cyclically referenced in [a -> b -> c -> !a]")
    }

    /// Verify that referecing a non-existent template will throw `LeafError.noTemplateExists`
    func testDependencyError() {
        files["/a.leaf"] = "#inline(\"b\")"
        files["/b.leaf"] = "#inline(\"c\")"
        
        try AssertErrors(render("a"), contains: "No template found for `c`")
    }
}
