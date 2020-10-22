/// Place all tests here originating from https://github.com/vapor/leaf-kit here
/// Suffix test name with issue # (eg, `testGH33()`)

import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class GHLeafKitIssuesTest: LeafTestClass {
    /// https://github.com/vapor/leaf-kit/issues/33
    func testGH33() throws {
        let test = LeafTestFiles()
        test.files["/base.leaf"] = """
        <body>
            Directly inlined snippet
            #inline("partials/picture.svg")

            #evaluate(body)
        </body>
        """
        test.files["/page.leaf"] = """
        #define(body):
        Snippet added through define/evaluate
        #inline("partials/picture.svg")
        #enddefine
        #inline("base")
        """
        test.files["/partials/picture.svg"] = """
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

        let renderer = TestRenderer(sources: .singleSource(test))
        let page = try renderer.render(path: "page").wait()
        XCTAssertEqual(page.string, expected)
    }

    /// https://github.com/vapor/leaf-kit/issues/50
    func testGH50() throws {
        let test = LeafTestFiles()
        test.files["/a.leaf"] = """
        #export(body):
        #for(challenge in challenges):
        #extend("a/b-c-d")
        #endfor
        #endexport
        #extend("a/b")
        """
        test.files["/a/b.leaf"] = "#import(body)"
        test.files["/a/b-c-d.leaf"] = "HI\n"

        let expected = """
        HI
        HI
        HI

        """

        let renderer = TestRenderer(sources: .singleSource(test))
        let page = try renderer.render(path: "a", context: ["challenges":["","",""]]).wait()
        XCTAssertEqual(page.terse, expected)
    }
}
