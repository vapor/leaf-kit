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

        let error = await #expect(throws: LeafError.self) {
            try await TestRenderer(sources: .init(singleSource: test)).render(path: "a")
        }

        guard case .cyclicalReference(let name, let cycle) = error else {
            Issue.record("Expected .cyclicalReference(a, [a, b, c, a]), got \($0.localizedDescription)")
        }

        #expect(error.reason.name == "a")
        #expect(error.reason.cycle == ["a", "b", "c", "a"])
    }

    /// Verify that referencing a non-existent template will throw `LeafError.noTemplateExists`
    @Test func testDependencyError() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = "#extend(\"b\")"
        test.files["/b.leaf"] = "#extend(\"c\")"

        let error = await #expect(throws: LeafError.self) {
            try await TestRenderer(sources: .init(singleSource: test)).render(path: "a")
        }

        guard case .noTemplateExists(let name) = error.reason else {
            Issue.record("Expected .noTemplateExists(c), got \(error.localizedDescription)")
            return
        }

        #expect(name == "c")
    }

    /// Verify that rendering a template with a missing required parameter will throw `LeafError.missingParameter`
    @Test func testMissingParameterError() async throws {
        var test = TestFiles()
        // Assuming "/missingParam.leaf" is a template that requires a parameter we intentionally don't provide
        test.files["/missingParam.leaf"] = """
            #(foo.bar.trim())
            """

        let error = await #expect(throws: LeafError.self) {
            try await TestRenderer(sources: .init(singleSource: test)).render(path: "missingParam", context: [:])
        }

        guard case .unknownError(let message) = error.reason else {
            Issue.record("Expected .unknownError(Found nil while iterating through params), got \(error.localizedDescription)")
            return
        }

        #expect(message == "Found nil while iterating through params")
    }
}
