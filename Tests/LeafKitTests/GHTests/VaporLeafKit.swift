/// Place all tests here originating from https://github.com/vapor/leaf-kit here
/// Suffix test name with issue # (eg, `testGH33()`)

@testable import XCTLeafKit

final class GHLeafKitIssuesTest: MemoryRendererTestCase {
    /// https://github.com/vapor/leaf-kit/issues/33
    func testGH33() throws {
        files["/base.leaf"] = """
        <body>
            Directly inlined snippet
            #inline("partials/picture.svg")

            #evaluate(body)
        </body>
        """
        
        files["/page.leaf"] = """
        #define(body):
        Snippet added through define/evaluate
        #inline("partials/picture.svg")
        #enddefine
        #inline("base")
        """
        
        files["/partials/picture.svg"] = """
            <svg><path d="M0..."></svg>
        
        """

        let expected = """
        <body>
            Directly inlined snippet
            <svg><path d="M0..."></svg>

            Snippet added through define/evaluate
            <svg><path d="M0..."></svg>
        </body>
        """

        try XCTAssertEqual(render("page"), expected)
    }

    /// https://github.com/vapor/leaf-kit/issues/50
    func testGH50() throws {
        files["/a.leaf"] = """
        #define(body):
        #for(challenge in challenges):
        #inline("a/b-c-d")
        #endfor
        #enddefine
        #inline("a/b")
        """
        
        files["a/b"] = "#evaluate(body)"
        files["a/b-c-d"] = "HI\n"

        let expected = """
        HI
        HI
        HI

        """

        try XCTAssertEqual(render("a", ["challenges": ["","",""]]), expected)
    }
}
