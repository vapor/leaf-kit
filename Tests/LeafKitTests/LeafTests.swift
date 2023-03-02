@testable import LeafKit
import XCTest

final class LeafTests: XCTestCase {

    // conversation ongoing
    func testCommentSugar() throws {
        let template = """
        #("foo")
        #comment:
            this is a comment!
        #endcomment
        bar
        """
        try XCTAssertEqual(render(template), "foo\n\nbar")
    }

    func testHashtag() throws {
        let template = """
        #("hi") #thisIsNotATag...
        """
        try XCTAssertEqual(render(template), "hi #thisIsNotATag...")
    }

    // conversation ongoing
    func testComplexIf() throws {
        let template = """
        #if(a): #if(b): hallo #else: #if(c): dallo #else: ballo #endif #endif #endif
        """

        let expectation = """
        ballo
        """
        let rendered = try render(template, ["a": .string("true")])
        XCTAssertEqual(
            rendered.trimmingCharacters(in: .whitespacesAndNewlines),
            expectation.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

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

    func testNested() throws {
        let template = """
        <p>#(lowercased(foo))</p>
        """
        try XCTAssertEqual(render(template, ["foo": "BAR"]), "<p>bar</p>")
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
        #if(false):Bad1#elseif(true):Good#else:Bad2#endif
        """
        try XCTAssertEqual(render(template), "Good")
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

    func testStringIf() throws {
        let template = """
        #if(name):Hello, #(name)!#else:No Name!#endif
        """
        let expectedName = "Hello, Tanner!"
        let expectedNoName = "No Name!"
        try XCTAssertEqual(render(template, ["name": .string("Tanner")]), expectedName)
        try XCTAssertEqual(render(template), expectedNoName)
    }

    func testEqualIf() throws {
        let template = """
        #if(string1 == string2):Good#else:Bad#endif
        """
        let expectedGood = "Good"
        let expectedBad = "Bad"
        try XCTAssertEqual(render(template, ["string1": .string("Tanner"), "string2": .string("Tanner")]), expectedGood)
        try XCTAssertEqual(render(template, ["string1": .string("Tanner"), "string2": .string("n/a")]), expectedBad)
    }

    func testAndStringIf() throws {
        let template = """
        #if(name && one):Hello, #(name)#(one)!#elseif(name):Hello, #(name)!#else:No Name!#endif
        """
        let expectedNameOne = "Hello, Tanner1!"
        let expectedName = "Hello, Tanner!"
        let expectedNoName = "No Name!"
        try XCTAssertEqual(render(template, ["name": .string("Tanner"), "one": .string("1")]), expectedNameOne)
        try XCTAssertEqual(render(template, ["name": .string("Tanner")]), expectedName)
        try XCTAssertEqual(render(template), expectedNoName)
    }

    func testOrStringIf() throws {
        let template = """
        #if(name || one):Hello, #(name)#(one)!#else:No Name!#endif
        """
        let expectedName = "Hello, Tanner!"
        let expectedOne = "Hello, 1!"
        let expectedNoName = "No Name!"
        try XCTAssertEqual(render(template, ["name": .string("Tanner")]), expectedName)
        try XCTAssertEqual(render(template, ["one": .string("1")]), expectedOne)
        try XCTAssertEqual(render(template), expectedNoName)
    }

    func testArrayIf() throws {
        let template = """
        #if(namelist):#for(name in namelist):Hello, #(name)!#endfor#else:No Names!#endif
        """
        let expectedNames = "Hello, Tanner!"
        let expectedNoNames = "No Names!"
        try XCTAssertEqual(render(template, ["namelist": [.string("Tanner")]]), expectedNames)
        try XCTAssertEqual(render(template), expectedNoNames)
    }

    func testEscapeTag() throws {
        let template = """
        #("foo") \\#("bar")
        """
        let expected = """
        foo #("bar")
        """
        try XCTAssertEqual(render(template, [:]), expected)
    }

    func testCount() throws {
        let template = """
        count: #count(array)
        """
        let expected = """
        count: 4
        """
        try XCTAssertEqual(render(template, ["array": ["","","",""]]), expected)
    }

    func testDateFormat() throws {
        let template = """
        Date: #date(foo, "yyyy-MM-dd")
        """

        let expected = """
        Date: 1970-01-16
        """
        try XCTAssertEqual(render(template, ["foo": 1_337_000]), expected)

    }

    func testWith() throws {
        let template = """
        #with(parent):#(child)#endwith
        """
        let expected = """
        Elizabeth
        """

        try XCTAssertEqual(render(template, ["parent": ["child": "Elizabeth"]]), expected)
    }

    func testExtendWithSugar() throws {
        var test = TestFiles()
        test.files["/header.leaf"] = """
        <h1>#(child)</h1>
        """
        test.files["/base.leaf"] = """
        #extend("header", parent)
        """
        let expected = """
        <h1>Elizabeth</h1>
        """

        let renderer = TestRenderer(sources: .singleSource(test))

        let page = try renderer.render(path: "base", context: ["parent": ["child": "Elizabeth"]]).wait()
        XCTAssertEqual(page.string, expected)
    }

    func testDictionaryForLoop() throws {
        try XCTAssertEqual(render("""
        #for(key, value in ["orwell": "1984"]):literally #(value) by george #(key)#endfor
        """), """
        literally 1984 by george orwell
        """)

        try XCTAssertEqual(render("""
        #for(key, value in ["orwell": "1984", "jorjor": "1984"]):#(value)#endfor
        """), """
        19841984
        """)
    }

    func testEmptyForLoop() throws {
        let template = """
        #for(category in categories):
            <a class=“dropdown-item” href=“#”>#(category.name)</a>
        #endfor
        """
        let expected = """
        """

        struct Category: Encodable {
            var name: String
        }

        struct Context: Encodable {
            var categories: [Category]
        }
        
        try XCTAssertEqual(render(template, ["categories": []]), expected)

    }

    func testKeyEqual() throws {
        let template = """
        #if(title == "foo"):it's foo#else:not foo#endif
        """
        let expected = """
        it's foo
        """

        struct Stuff: Encodable {
            var title: String
        }

        try XCTAssertEqual(render(template, ["title": "foo"]), expected)
    }

    func testLoopIndices() throws {
        let template = """
        #for(name in names):
            #(name) - index=#(index) last=#(isLast) first=#(isFirst)
        #endfor
        """
        let expected = """

            tanner - index=0 last=false first=true

            ziz - index=1 last=false first=false

            vapor - index=2 last=true first=false

        """

        try XCTAssertEqual(render(template, ["names": ["tanner", "ziz", "vapor"]]), expected)
    }

    func testNestedLoopIndices() throws {
        let template = """
        #for(array in arrays):
        Array#(index) - [#for(element in array): #(index)#if(isFirst):(first)#elseif(isLast):(last)#endif : "#(element)"#if(!isLast):, #endif#endfor]#endfor
        """
        let expected = """

        Array0 - [ 0(first) : "zero",  1 : "one",  2(last) : "two"]
        Array1 - [ 0(first) : "a",  1 : "b",  2(last) : "c"]
        Array2 - [ 0(first) : "red fish",  1 : "blue fish",  2(last) : "green fish"]
        """

        let data = LeafData.array([
            LeafData.array(["zero", "one", "two"]),
            LeafData.array(["a", "b", "c"]),
            LeafData.array(["red fish", "blue fish", "green fish"])
        ])

        try XCTAssertEqual(render(template, ["arrays": data]), expected)
    }

    // It would be nice if a pre-render phase could catch things like calling
    // tags that would normally ALWAYS throw in serializing (eg, calling index
    // when not in a loop) so that warnings can be provided and AST can be minimized.
    func testLoopTagsInvalid() throws {
        let template = """
            #if(isFirst):Wrong#else:Right#endif
            """
            let expected = "Right"

        try XCTAssertEqual(render(template, [:]), expected)
    }

    // Current implementation favors context keys over tag keys, so
    // defining a key for isFirst in context will override accessing registered
    // LeafTags with the same name.
    // More reason to introduce scoping tag keys!!
    func testTagContextOverride() throws {
        let template = """
            #if(isFirst):Wrong (Maybe)#else:Right#endif
            """
            let expected = "Wrong (Maybe)"

        try XCTAssertEqual(render(template, ["isFirst": true]), expected)
    }
  
    // Validate parse resolution of negative numbers
    func testNegatives() throws {
        let input = """
        #(10)
        #(-10)
        """

        let syntax = """
        (substitution (integer))
        (raw)
        (substitution (- (integer)))
        """

        let expectation = """
        10
        -10
        """

        let parsed = try parse(input)
        assertSExprEqual(parsed.sexpr(), syntax)

        try XCTAssertEqual(render(input), expectation)
    }

    // Validate parsing and evaluation of array literals
    func testArrayLiterals() throws {
        let input = """
        #for(item in []):#(item)#endfor
        #for(item in [1]):#(item)#endfor
        #for(item in ["hi"]):#(item)#endfor
        #for(item in [1, "hi"]):#(item)#endfor
        """

        let syntax = """
        (for (array_literal) (substitution(variable))) (raw)
        (for (array_literal (integer)) (substitution(variable))) (raw)
        (for (array_literal(string)) (substitution(variable))) (raw)
        (for (array_literal(integer) (string)) (substitution(variable)))
        """

        let expectation = """

        1
        hi
        1hi
        """

        let parsed = try parse(input)
        assertSExprEqual(parsed.sexpr(), syntax)

        try XCTAssertEqual(render(input), expectation)
    }

    // Validate parsing and evaluation of dictionary literals
    func testDictionaryLiterals() throws {
        let input = """
        #with(["hi": "world"]):#(hi)#endwith
        """

        let syntax = """
        (with (dictionary_literal ((string)(string)))
            (substitution(variable)))
        """

        let expectation = """
        world
        """

        let parsed = try parse(input)
        assertSExprEqual(parsed.sexpr(), syntax)

        try XCTAssertEqual(render(input), expectation)
    }

    // Validate parse resolution of evaluable expressions
    func testComplexParameters() throws {
        let input = """
        #(index-5)
        #(10-5)
        #(10 - 5)
        #(-5)
        """

        let expectation = """
        5
        5
        5
        -5
        """

        try XCTAssertEqual(render(input,["index":10]), expectation)
    }

    // Validate parse resolution of negative numbers
    func testOperandGrouping() throws {
        let input = """
        #(!true&&!false)
        #((!true) || (!false))
        #((true) && (!false))
        #((!true) || (false))
        #(!true || !false)
        #(true)
        """

        let expectation = """
        false
        true
        true
        false
        true
        true
        """

        try XCTAssertEqual(render(input), expectation)
    }
}
