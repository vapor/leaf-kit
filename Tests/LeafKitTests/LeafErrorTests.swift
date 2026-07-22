/// Place all tests related to verifying that errors ARE thrown here.

import Testing

@testable import LeafKit

@Suite
struct LeafErrorTests {
    /// Verify that cyclical references via #extend will throw `LeafError.cyclicalReference`
    @Test func testCyclicalError() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"
        test.files["/c.leaf"] = "#extend(\"a\")"

        await #expect(throws: LeafError.cyclicalReference("a", chain: ["a", "b", "c", "a"])) {
            try await TestRenderer(sources: .init(singleSource: test)).render(path: "a")
        }
    }

    /// Verify that referencing a non-existent template will throw `LeafError.noTemplateExists`
    @Test func testDependencyError() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"

        await #expect(throws: LeafError.noTemplateExists(at: "c").self) {
            try await TestRenderer(sources: .init(singleSource: test)).render(path: "a")
        }
    }

    /// Verify that rendering a template with a missing required parameter will throw `LeafError.missingParameter`
    @Test func testMissingParameterError() async throws {
        var test = TestFiles()
        // Assuming "/missingParam.leaf" is a template that requires a parameter we intentionally don't provide
        test.files["/missingParam.leaf"] = """
            #(foo.bar.trim())
            """

        await #expect(throws: LeafError.unknownError("Found nil while iterating through params").self) {
            try await TestRenderer(sources: .init(singleSource: test)).render(path: "missingParam", context: [:])
        }
    }
}
