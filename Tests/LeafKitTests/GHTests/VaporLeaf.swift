/// Place all tests originating from https://github.com/vapor/leaf here.
/// Suffix test name with issue # (e.g., `testGH33()`)

@testable import LeafKit
import NIOConcurrencyHelpers
import XCTest

final class GHLeafIssuesTest: XCTestCase {
    /// https://github.com/vapor/leaf/issues/96
    func testGH96() throws {
        let template = """
        #for(name in names):
            #(name): index=#(index) last=#(isLast) first=#(isFirst)
        #endfor
        """
        let expected = """

            tanner: index=0 last=false first=true

            ziz: index=1 last=false first=false

            vapor: index=2 last=true first=false

        """
        try XCTAssertEqual(render(template, ["names": ["tanner", "ziz", "vapor"]]), expected)
    }
    
    /// https://github.com/vapor/leaf/issues/99
    func testGH99() throws {
        let template = """
        Hi #(first) #(last)
        """
        let expected = """
        Hi Foo Bar
        """
        try XCTAssertEqual(render(template, ["first": "Foo", "last": "Bar"]), expected)
    }

    /// https://github.com/vapor/leaf/issues/101
    func testGH101() throws {
        let template = """
        #for(foo in foos):#(index+1):#(foo)#endfor
        """
        let expected = "1:A2:B3:C"
        try XCTAssertEqual(render(template, ["foos": ["A", "B", "C"]]), expected)
    }
    
    /// https://github.com/vapor/leaf/issues/105
    func testGH105() throws {
        do {
            let template = """
            #if(1 + 1 == 2):hi#endif
            """
            let expected = "hi"
            try XCTAssertEqual(render(template, ["a": "a"]), expected)
        }
        do {
            let template = """
            #if(2 == 1 + 1):hi#endif
            """
            let expected = "hi"
            try XCTAssertEqual(render(template, ["a": "a"]), expected)
        }
        do {
            let template = """
            #if(1 == 1 + 1 || 1 == 2 - 1):hi#endif
            """
            let expected = "hi"
            try XCTAssertEqual(render(template, ["a": "a"]), expected)
        }
    }

    // https://github.com/vapor/leaf/issues/127
    func testGH127Inline() throws {
        do {
            let template = """
            <html>
            <head>
            <title></title>#comment: Translate all copy!!!!! #endcomment
            <style>
            """
            let expected = """
            <html>
            <head>
            <title></title>
            <style>
            """
            try XCTAssertEqual(render(template, ["a": "a"]), expected)
        }
    }
}
