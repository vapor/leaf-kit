/// Place all tests originating from https://github.com/vapor/leaf-kit here.
/// Suffix test name with issue # (e.g., `testGH33()`).

import NIOConcurrencyHelpers
import Testing

@testable import LeafKit

@Suite
struct GHLeafKitIssuesTest {
    /// https://github.com/vapor/leaf-kit/issues/33
    func testGH33() async throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
            <body>
                Directly extended snippet
                #extend("partials/picture.svg"):#endextend
                #import("body")
            </body>
            """
        test.files["/page.leaf"] = """
            #extend("base"):
                #export("body"):
                Snippet added through export/import
                #extend("partials/picture.svg"):#endextend
            #endexport
            #endextend
            """
        test.files["/partials/picture.svg"] = """
            <svg><path d="M0..."></svg>
            """

        let expected = """
            <body>
                Directly extended snippet
                <svg><path d="M0..."></svg>
                
                Snippet added through export/import
                <svg><path d="M0..."></svg>

            </body>
            """

        #expect(try await TestRenderer(sources: .init(singleSource: test)).render(path: "page").string == expected)
    }

    /// https://github.com/vapor/leaf-kit/issues/50
    func testGH50() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = """
            #extend("a/b"):
            #export("body"):#for(challenge in challenges):
            #extend("a/b-c-d"):#endextend#endfor
            #endexport
            #endextend
            """
        test.files["/a/b.leaf"] = """
            #import("body")
            """
        test.files["/a/b-c-d.leaf"] = """
            HI
            """

        let expected = """

            HI
            HI
            HI

            """

        #expect(
            try await TestRenderer(sources: .init(singleSource: test)).render(path: "a", context: ["challenges": ["", "", ""]]).string
                == expected)
    }

    /// https://github.com/vapor/leaf-kit/issues/87
    func testGH87() {
        let template1 = """
            #if(2 % 2 == 0):hi#endif #if(0 == 4 % 2):there#endif
            """
        let expected1 = "hi there"
        #expect(try render(template1, ["a": "a"]) == expected1)

        // test with double values
        let template2 = """
            #if(5.0 % 2.0 == 1.0):hi#endif #if(4.0 % 2.0 == 0.0):there#endif
            """
        let expected2 = "hi there"
        #expect(try render(template2, ["a": "a"]) == expected2)
    }

    /// https://github.com/vapor/leaf-kit/issues/84
    func testGH84() async throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
            <body>
                Unfound import test:#import("body")
            </body>
            """
        test.files["/page.leaf"] = """
            #extend("base"):
            #endextend
            """

        let expected = """
            <body>
                Unfound import test:
            </body>
            """

        // Page renders as expected. Unresolved import is ignored.
        #expect(try await TestRenderer(sources: .init(singleSource: test)).render(path: "page").string == expected)

        // Page rendering throws expected error
        let config = LeafConfiguration(rootDirectory: "/", tagIndicator: LeafConfiguration.tagIndicator, ignoreUnfoundImports: false)

        await #expect(throws: LeafError.unknownError("import(\"body\") should have been resolved BEFORE serialization")) {
            try await TestRenderer(configuration: config, sources: .init(singleSource: test)).render(path: "page")
        }
    }
}
