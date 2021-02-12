/// Place all tests here originating from https://github.com/vapor/leaf-kit here
/// Suffix test name with issue # (eg, `testGH33()`)

import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class GHLeafKitIssuesTest: XCTestCase {
    
    /// https://github.com/vapor/leaf-kit/issues/33
    func testGH33() {
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

        let page = try! TestRenderer(sources: .singleSource(test)).render(path: "page").wait()
        XCTAssertEqual(page.string, expected)
    }
    
    
    /// https://github.com/vapor/leaf-kit/issues/50
    func testGH50() {
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

        let page = try! TestRenderer(sources: .singleSource(test)).render(path: "a", context: ["challenges":["","",""]]).wait()
            XCTAssertEqual(page.string, expected)
    }
    
    /// https://github.com/vapor/leaf-kit/issues/87
    func testGH87() {
        do {
            let template = """
            #if(2 % 2 == 0):hi#endif #if(0 == 4 % 2):there#endif
            """
            let expected = "hi there"
            try XCTAssertEqual(render(template, ["a": "a"]), expected)
        }
        
        // test with double values
        do {
            let template = """
            #if(5.0 % 2.0 == 1.0):hi#endif #if(4.0 % 2.0 == 0.0):there#endif
            """
            let expected = "hi there"
            try XCTAssertEqual(render(template, ["a": "a"]), expected)
        }
    }
}
