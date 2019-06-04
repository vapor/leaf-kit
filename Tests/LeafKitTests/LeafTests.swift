@testable import LeafKit
import XCTest

final class LeafTests: XCTestCase {
    func testRaw() throws {
        let template = "Hello!"
        try XCTAssertEqual(render(template), "Hello!")
    }

    func testPrint() throws {
        let template = "Hello, #(name)!"
        try XCTAssertEqual(render(template, ["name": "Tanner"]), "Hello, Tanner!")
    }

    func testConstant() throws {
        let template = "<h1>#(42)</h1>"
        try XCTAssertEqual(render(template), "<h1>42</h1>")
    }

    func testInterpolated() throws {
        let template = """
        <p>#("foo: #(foo)")</p>
        """
        try XCTAssertEqual(render(template, ["foo": "bar"]), "<p>foo: bar</p>")
    }

    func testNested() throws {
        let template = """
        <p>#(embed(foo))</p>
        """
        try XCTAssertEqual(render(template, ["foo": "bar"]), "<p>You have loaded bar.leaf!\n</p>")
    }

    func testExpression() throws {
        let template = "#(age > 99)"
        try XCTAssertEqual(render(template, ["age": 21]), "false")
        try XCTAssertEqual(render(template, ["age": 150]), "true")
    }

    func testBody() throws {
        let template = """
        #if(show):hi#endif
        """
        try XCTAssertEqual(render(template, ["show": false]), "")
        try XCTAssertEqual(render(template, ["show": true]), "hi")
    }

    func testRuntime() throws {
        // FIXME: need to run var/exports first and in order
        let template = """
            #set("foo", "bar")
            Runtime: #(foo)
        """
        try XCTAssert(render(template).contains("Runtime: bar"))
    }

    func testEmbed() throws {
        let template = """
        #embed("hello")
        """
        try XCTAssertEqual(render(template), "Hello, world!\n")
    }

    func testForSugar() throws {
        let template = """
        <p>
            <ul>
                #for(name in names):<li>#(name)</li>#endfor
            </ul>
        </p>
        """
        let expect = """
        <p>
            <ul>
                <li>Vapor</li><li>Leaf</li><li>Bits</li>
            </ul>
        </p>
        """
        try XCTAssertEqual(render(template, ["names": ["Vapor", "Leaf", "Bits"]]), expect)
    }

    func testIfSugar() throws {
        let template = """
        #if(false):Bad#elseif(true):Good#else:Bad#endif
        """
        try XCTAssertEqual(render(template), "Good")
    }

    func testCommentSugar() throws {
        let template = """
        #("foo")
        #// this is a comment!
        bar
        """

        let multilineTemplate = """
        #("foo")
        #/*
            this is a comment!
        */
        bar
        """
        try XCTAssertEqual(render(template), "foo\nbar")
        try XCTAssertEqual(render(multilineTemplate), "foo\n\nbar")
    }

    func testHashtag() throws {
        let template = """
        #("hi") #thisIsNotATag...
        """
        try XCTAssertEqual(render(template), "hi #thisIsNotATag...")
    }

    func testNot() throws {
        let template = """
        #if(!false):Good#endif#if(!true):Bad#endif
        """
        try XCTAssertEqual(render(template), "Good")
    }

    func testNestedBodies() throws {
        let template = """
        #if(true):#if(true):Hello#endif#endif
        """
        try XCTAssertEqual(render(template), "Hello")
    }

    func testDotSyntax() throws {
        let template = """
        #if(user.isAdmin):Hello, #(user.name)!#endif
        """
        try XCTAssertEqual(render(template, ["user": ["isAdmin": true, "name": "Tanner"]]), "Hello, Tanner!")
    }

    func testEqual() throws {
        let template = """
        #if(id == 42):User 42!#endif#if(id != 42):Shouldn't show up#endif
        """
        try XCTAssertEqual(render(template, ["id": 42, "name": "Tanner"]), "User 42!")
    }
//
//    func testEscapeExtraneousBody() throws {
//        let template = """
//        extension #("User") \\{
//
//        }
//        """
//        let expected = """
//        extension User {
//
//        }
//        """
//        try XCTAssertEqual(renderer.testRender(template, .null), expected)
//    }
//
//
//    func testEscapeTag() throws {
//        let template = """
//        #("foo") \\#("bar")
//        """
//        let expected = """
//        foo #("bar")
//        """
//        try XCTAssertEqual(renderer.testRender(template, .null), expected)
//    }
//
//    func testCount() throws {
//        let template = """
//        count: #count(array)
//        """
//        let expected = """
//        count: 4
//        """
//        let context = TemplateData.dictionary(["array": .array([.null, .null, .null, .null])])
//        try XCTAssertEqual(renderer.testRender(template, context), expected)
//    }
//
//    func testNestedSet() throws {
//        let template = """
//        #if(a){#set("title"){A}}title: #get(title)
//        """
//        let expected = """
//        title: A
//        """
//
//        let context = TemplateData.dictionary(["a": .bool(true)])
//        try XCTAssertEqual(renderer.testRender(template, context), expected)
//    }
//
//    func testDateFormat() throws {
//        let template = """
//        Date: #date(foo, "yyyy-MM-dd")
//        """
//
//        let expected = """
//        Date: 1970-01-16
//        """
//
//        let context = TemplateData.dictionary(["foo": .double(1_337_000)])
//        try XCTAssertEqual(renderer.testRender(template, context), expected)
//
//    }
//
//    func testStringIf() throws {
//        let template = "#if(name){Hello, #(name)!}"
//        let expected = "Hello, Tanner!"
//        let context = TemplateData.dictionary(["name": .string("Tanner")])
//        try XCTAssertEqual(renderer.testRender(template, context), expected)
//    }
//
//    func testEmptyForLoop() throws {
//        let template = """
//        #for(category in categories) {
//            <a class=“dropdown-item” href=“#”>#(category.name)</a>
//        }
//        """
//        let expected = """
//        """
//
//        struct Category: Encodable {
//            var name: String
//        }
//
//        struct Context: Encodable {
//            var categories: [Category]
//        }
//
//        let context = Context(categories: [])
//        let data = try TemplateDataEncoder().testEncode(context)
//        try XCTAssertEqual(renderer.testRender(template, data), expected)
//
//    }
//
//    func testKeyEqual() throws {
//        let template = """
//        #if(title == "foo") {it's foo} else {not foo}
//        """
//        let expected = """
//        it's foo
//        """
//
//        struct Stuff: Encodable {
//            var title: String
//        }
//
//        let context = Stuff(title: "foo")
//        let data = try TemplateDataEncoder().testEncode(context)
//        try XCTAssertEqual(renderer.testRender(template, data), expected)
//    }
//
//    func testInvalidForSyntax() throws {
//        let data = try TemplateDataEncoder().testEncode(["names": ["foo"]])
//        do {
//            _ = try renderer.testRender("#for( name in names) {}", data)
//            XCTFail("Whitespace not allowed here")
//        } catch {
//            XCTAssert("\(error)".contains("space not allowed"))
//        }
//
//        do {
//            _ = try renderer.testRender("#for(name in names ) {}", data)
//            XCTFail("Whitespace not allowed here")
//        } catch {
//            XCTAssert("\(error)".contains("space not allowed"))
//        }
//
//        do {
//            _ = try renderer.testRender("#for( name in names ) {}", data)
//            XCTFail("Whitespace not allowed here")
//        } catch {
//            XCTAssert("\(error)".contains("space not allowed"))
//        }
//
//        do {
//            _ = try renderer.testRender("#for(name in names) {}", data)
//        } catch {
//            XCTFail("\(error)")
//        }
//    }
//
//    func testTemplating() throws {
//        let home = """
//        #set("title", "Home")#set("body"){<p>#(foo)</p>}#embed("base")
//        """
//        let expected = """
//        <title>Home</title>
//        <body><p>bar</p></body>
//
//        """
//        renderer.astCache = ASTCache()
//        defer { renderer.astCache = nil }
//        let data = try TemplateDataEncoder().testEncode(["foo": "bar"])
//        try XCTAssertEqual(renderer.testRender(home, data), expected)
//        try XCTAssertEqual(renderer.testRender(home, data), expected)
//    }
//
//    // https://github.com/vapor/leaf/issues/96
//    func testGH96() throws {
//        let template = """
//        #for(name in names) {
//            #(name): index=#(index) last=#(isLast) first=#(isFirst)
//        }
//        """
//        let expected = """
//
//            tanner: index=0 last=false first=true
//
//            ziz: index=1 last=false first=false
//
//            vapor: index=2 last=true first=false
//
//        """
//        let data = try TemplateDataEncoder().testEncode([
//            "names": ["tanner", "ziz", "vapor"]
//            ])
//        try XCTAssertEqual(renderer.testRender(template, data), expected)
//    }
//
//    // https://github.com/vapor/leaf/issues/99
//    func testGH99() throws {
//        let template = """
//        Hi #(first) #(last)
//        """
//        let expected = """
//        Hi Foo Bar
//        """
//        let data = try TemplateDataEncoder().testEncode([
//            "first": "Foo", "last": "Bar"
//            ])
//        try XCTAssertEqual(renderer.testRender(template, data), expected)
//    }
//
//    // https://github.com/vapor/leaf/issues/101
//    func testGH101() throws {
//        let template = """
//        #for(foo in foos){#(index+1):#(foo)}
//        """
//        let expected = "1:A2:B3:C"
//        let data = try TemplateDataEncoder().testEncode([
//            "foos": ["A", "B", "C"]
//            ])
//        try XCTAssertEqual(renderer.testRender(template, data), expected)
//    }
//
//    // https://github.com/vapor/leaf/issues/105
//    func testGH105() throws {
//        do {
//            let template = """
//            #if(1 + 1 == 2) {hi}
//            """
//            let expected = "hi"
//            let data = try TemplateDataEncoder().testEncode(["a": "a"])
//            try XCTAssertEqual(renderer.testRender(template, data), expected)
//        }
//        do {
//            let template = """
//            #if(2 == 1 + 1) {hi}
//            """
//            let expected = "hi"
//            let data = try TemplateDataEncoder().testEncode(["a": "a"])
//            try XCTAssertEqual(renderer.testRender(template, data), expected)
//        }
//        do {
//            let template = """
//            #if(1 == 1 + 1 || 1 == 2 - 1) {hi}
//            """
//            let expected = "hi"
//            let data = try TemplateDataEncoder().testEncode(["a": "a"])
//            try XCTAssertEqual(renderer.testRender(template, data), expected)
//        }
//    }
//
//    // https://github.com/vapor/leaf/issues/127
//    func testGH127Inline() throws {
//        do {
//            let template = """
//            <html>
//            <head>
//            <title></title>#// Translate all copy!!!!!
//            <style>
//            """
//            let expected = """
//            <html>
//            <head>
//            <title></title>
//            <style>
//            """
//            let data = try TemplateDataEncoder().testEncode(["a": "a"])
//            try XCTAssertEqual(renderer.testRender(template, data), expected)
//        }
//    }
//
//    func testGH127SingleLine() throws {
//        do {
//            let template = """
//            <html>
//            <head>
//            <title></title>
//            #// Translate all copy!!!!!
//            <style>
//            """
//            let expected = """
//            <html>
//            <head>
//            <title></title>
//            <style>
//            """
//            let data = try TemplateDataEncoder().testEncode(["a": "a"])
//            try XCTAssertEqual(renderer.testRender(template, data), expected)
//        }
//    }
}

private func render(name: String = "test-render", _ template: String, _ context: [String: LeafData] = [:]) throws -> String {
    var lexer = LeafLexer(name: name, template: template)
    let tokens = try lexer.lex()
    var parser = LeafParser(name: name, tokens: tokens)
    let ast = try parser.parse()
    var serializer = LeafSerializer(ast: ast, context: context)
    let view = try serializer.serialize()
    return view.getString(at: view.readerIndex, length: view.readableBytes) ?? ""
}
