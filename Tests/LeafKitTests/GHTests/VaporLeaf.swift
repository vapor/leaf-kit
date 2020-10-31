/// Place all tests here originating from https://github.com/vapor/leaf here
/// Suffix test name with issue # (eg, `testGH33()`)

import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class GHLeafIssuesTest: MemoryRendererTestCase {
    /// https://github.com/vapor/leaf/issues/96
    func testGH96() throws {
        files["template"] = """
        #for((index, name) in names):
            #(name): index=#(index) last=#(isLast) first=#(isFirst)
        #endfor
        """
        
        let expected = """
            tanner: index=0 last=false first=true
            ziz: index=1 last=false first=false
            vapor: index=2 last=true first=false

        """
        
        try XCTAssertEqual(render("template", ["names": ["tanner", "ziz", "vapor"]]), expected)
    }

    /// https://github.com/vapor/leaf/issues/99
    func testGH99() throws {
        files["template"] = "Hi #(first) #(last)"
        let expected = "Hi Foo Bar"
        
        try XCTAssertEqual(render("template", ["first": "Foo", "last": "Bar"]), expected)
    }

    /// https://github.com/vapor/leaf/issues/101
    func testGH101() throws {
        files["template"] = "#for((index, foo) in foos):#(index+1):#(foo)#endfor"
        let expected = "1:A2:B3:C"
        
        try XCTAssertEqual(render("template", ["foos": ["A", "B", "C"]]), expected)
    }

    /// https://github.com/vapor/leaf/issues/105
    func testGH105() throws {
        files["one"] = "#if(1 + 1 == 2):hi#endif"
        files["two"] = "#if(2 == 1 + 1):hi#endif"
        files["three"] = "#if(1 == 1 + 1 || 1 == 2 - 1):hi#endif"
        
        for key in files.keys { try XCTAssertEqual(render(key, ["a": "a"]), "hi") }
    
    }
}

/// Archived tests no longer applicable
final class GHLeafIssuesTestArchive: MemoryRendererTestCase {
    // https://github.com/vapor/leaf/issues/127
    // TODO: This commenting style is not used anymore but needs a replacement
    func _testGH127Inline() throws {
        do {
            let template = """
            <html>
            <head>
            <title></title>#// Translate all copy!!!!!
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

    // TODO: This commenting style is not used anymore but needs a replacement
    func _testGH127SingleLine() throws {
        do {
            let template = """
            <html>
            <head>
            <title></title>
            #// Translate all copy!!!!!
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
