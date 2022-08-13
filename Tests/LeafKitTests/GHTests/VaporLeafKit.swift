/// Place all tests here originating from https://github.com/vapor/leaf-kit here
/// Suffix test name with issue # (eg, `testGH33()`)

import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class GHLeafKitIssuesTest: XCTestCase {
    
    /// https://github.com/vapor/leaf-kit/issues/33
    func testGH33() throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
        <body>
            Directly extended snippet
            #extend("partials/picture.svg")
            #import("body")
        </body>
        """
        test.files["/page.leaf"] = """
        #extend("base"):
            #export("body"):
                Snippet added through export/import
                #extend("partials/picture.svg")
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

        let page = try TestRenderer(sources: .singleSource(test)).render(path: "page").wait()
        XCTAssertEqual(page.string, expected)
    }
    
    
    /// https://github.com/vapor/leaf-kit/issues/50
    func testGH50() throws {
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

        let page = try TestRenderer(sources: .singleSource(test)).render(path: "a", context: ["challenges":["","",""]]).wait()
            XCTAssertEqual(page.string, expected)
    }
    
    /// https://github.com/vapor/leaf-kit/issues/87
    func testGH87() throws {
        let template = """
        #if((2 % 2) == 0):hi#endif #if(0 == (4 % 2)):there#endif
        """
        let expected = "hi there"
        try XCTAssertEqual(render(template, ["a": "a"]), expected)
    }
    
    /// https://github.com/vapor/leaf-kit/issues/84
    func testGH84() throws {
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
        let config1 = LeafConfiguration(rootDirectory: "/", tagIndicator: Character.tagIndicator, ignoreUnfoundImports: true)
        let page = try TestRenderer(configuration: config1, sources: .singleSource(test)).render(path: "page").wait()
        XCTAssertEqual(page.string, expected)
        
        // Page rendering throws expected error
        let config2 = LeafConfiguration(rootDirectory: "/", tagIndicator: Character.tagIndicator, ignoreUnfoundImports: false)
        XCTAssertThrowsError(try TestRenderer(configuration: config2, sources: .singleSource(test)).render(path: "page").wait()) { error in
            XCTAssertEqual((error as! LeafError).reason, .importNotFound(name: "body"))
        }
    }
}
