@testable import LeafKit
import XCTest

final class LeafMiscTests: MemoryRendererTestCase {
    /// currently not supported.. discussion ongoing
    func _testInterpolated() throws {
        let template = #"<p>#("foo: \\(foo)")</p>"#
        try XCTAssertEqual(render(raw: template, ["foo": "bar"]), "<p>foo: bar</p>")
    }

    func testComment() throws {
        let comment = """
        #("foo")
        #(# this is a comment #)
        bar
        """
        
        let multiline = """
        #("foo")
        #(#
            this is a comment!
        #)
        bar
        """
        
        try XCTAssertEqual(render(raw: comment), "foo\n\nbar")
        try XCTAssertEqual(render(raw: multiline), "foo\n\nbar")
    }

    func testHashtag() throws {
        let raw = #"#("hi") #thisIsNotATag..."#
        try XCTAssertEqual(render(raw: raw), "hi #thisIsNotATag...")
    }

    func testComplexIf() throws {
        LKROption.missingVariableThrows = false
        let raw = "#if(a): #if(b): hallo #else: #if(c): dallo #else: ballo #endif #endif #endif"
        try XCTAssertEqual(render(raw: raw, ["a": true]).trimmed, "ballo")
    }

    func testRaw() throws {
        let template = "Hello!"
        try XCTAssertEqual(render(raw: template), "Hello!")
    }

    func testPrint() throws {
        let template = "Hello, #(name)!"
        try XCTAssertEqual(render(raw: template, ["name": "Tanner"]), "Hello, Tanner!")
    }

    func testConstant() throws {
        let template = "<h1>#(42)</h1>"
        try XCTAssertEqual(render(raw: template), "<h1>42</h1>")
    }

    func testNested() throws {
        let template = #"<p>#(foo.lowercased())</p>"#
        try XCTAssertEqual(render(raw: template, ["foo": "BAR"]), "<p>bar</p>")
    }

    func testExpression() throws {
        let template = "#(age > 99)"
        try XCTAssertEqual(render(raw: template, ["age": 21]), "false")
        try XCTAssertEqual(render(raw: template, ["age": 150]), "true")
    }

    func testBody() throws {
        let template = #"#if(show):hi#endif"#
        try XCTAssertEqual(render(raw: template, ["show": false]), "")
        try XCTAssertEqual(render(raw: template, ["show": true]), "hi")
    }

    func testForSugar() throws {
        let template = """
        <p>
            <ul>
                #for(name in names):
                <li>#(name)</li>
                #endfor
            </ul>
        </p>
        """
        let expect = """
        <p>
            <ul>
                <li>Vapor</li>
                <li>Leaf</li>
                <li>Bits</li>
            </ul>
        </p>
        """
        try XCTAssertEqual(render(raw: template, ["names": ["Vapor", "Leaf", "Bits"]]), expect)
    }

    func testIfSugar() throws {
        let template = #"#if(false):Bad#elseif(true):Good#else:Bad#endif"#
        try XCTAssertEqual(render(raw: template), "Good")
    }

    func testNot() throws {
        let template = #"#if(!false):Good#endif#if(!true):Bad#endif"#
        try XCTAssertEqual(render(raw: template), "Good")
    }

    func testNestedBodies() throws {
        let template = #"#if(true):#if(true):Hello#endif#endif"#
        try XCTAssertEqual(render(raw: template), "Hello")
    }

    func testDotSyntax() throws {
        let template = #"#if(user.isAdmin):Hello, #(user.name)!#endif"#
        try XCTAssertEqual(render(raw: template,
                                  ["user": ["isAdmin": true, "name": "Tanner"]]),
                           "Hello, Tanner!")
    }

    func testEqual() throws {
        let template = #"#if(id == 42):User 42!#endif#if(id != 42):Shouldn't show up#endif"#
        try XCTAssertEqual(render(raw: template, ["id": 42, "name": "Tanner"]), "User 42!")
    }

    func testStringIf() throws {
        LKROption.missingVariableThrows = false
        let template = #"#if(name):Hello, #(name)!#else:No Name!#endif"#
        try XCTAssertEqual(render(raw: template), "No Name!")
        try XCTAssertEqual(render(raw: template, ["name": .string("Tanner")]), "Hello, Tanner!")
    }

    func testEqualIf() throws {
        LKROption.missingVariableThrows = false
        let template = "#if(string1 == string2):Good#else:Bad#endif"
        try XCTAssertEqual(render(raw: template, ["string1": "Tanner", "string2": "Tanner"]), "Good")
        try XCTAssertEqual(render(raw: template, ["string1": "Tanner", "string2": "n/a"]), "Bad")
    }

    func testAndStringIf() throws {
        LKROption.missingVariableThrows = false
        let template = "#if(name && one):Hello, #(name)#(one)!#elseif(name):Hello, #(name)!#else:No Name!#endif"
        try XCTAssertEqual(render(raw: template, ["name": .string("Tanner"), "one": .string("1")]), "Hello, Tanner1!")
        try XCTAssertEqual(render(raw: template, ["name": .string("Tanner")]), "Hello, Tanner!")
        try XCTAssertEqual(render(raw: template), "No Name!")
    }

    func testOrStringIf() throws {
        LKROption.missingVariableThrows = false
        let template = "#if(name || one):Hello, #(name)#(one)!#else:No Name!#endif"
        try XCTAssertEqual(render(raw: template, ["name": .string("Tanner")]), "Hello, Tanner!")
        try XCTAssertEqual(render(raw: template, ["one": .string("1")]), "Hello, 1!")
        try XCTAssertEqual(render(raw: template), "No Name!")
    }

    func testArrayIf() throws {
        LKROption.missingVariableThrows = false
        let template = "#if(namelist):#for(name in namelist):Hello, #(name)!#endfor#else:No Name!#endif"
        try XCTAssertEqual(render(raw: template, ["namelist": [.string("Tanner")]]), "Hello, Tanner!")
        try XCTAssertEqual(render(raw: template), "No Name!")
    }

    func testEscapeTag() throws {
        let template = ###"#("foo") \#("bar")"###
        try XCTAssertEqual(render(raw: template), #"foo #("bar")"#)
    }

    func testCount() throws {
        let template = "count: #(array.count())"
        try XCTAssertEqual(render(raw: template, ["array": ["","","",""]]), "count: 4")
    }

    func testDateFormat() throws {
        LeafTimestamp.referenceBase = .unixEpoch
        let template = #"Date: #Date(timeStamp: foo, fixedFormat: "yyyy-MM-dd")"#
        try XCTAssertEqual(render(raw: template, ["foo": 1_337_000]), "Date: 1970-01-16")
    }

    func testLoopIndices() throws {
        let template = """
        #for((index, name) in names):
            #(name) - index=#(index) last=#(isLast) first=#(isFirst)
        #endfor
        """

        let expected = """
            tanner - index=0 last=false first=true
            ziz - index=1 last=false first=false
            vapor - index=2 last=true first=false

        """

        try XCTAssertEqual(render(raw: template, ["names": ["tanner", "ziz", "vapor"]]), expected)
    }

    func testNestedLoopIndices() throws {
        let template = """
        #for((index, array) in arrays):
        Array#(index) - [#for((index, element) in array):
        #(index)#if(isFirst):(first)#elseif(isLast):(last)#endif: "#(element)"#if(!isLast):, #endif#endfor]
        #endfor
        """
        let expected = """
        Array0 - [0(first): "zero", 1: "one", 2(last): "two"]
        Array1 - [0(first): "a", 1: "b", 2(last): "c"]
        Array2 - [0(first): "red fish", 1: "blue fish", 2(last): "green fish"]

        """

        let data: LeafData = .array([
            .array(["zero", "one", "two"]),
            .array(["a", "b", "c"]),
            .array(["red fish", "blue fish", "green fish"])
        ])

        try XCTAssertEqual(render(raw: template, ["arrays": data]), expected)
    }

    /// Validate parse resolution of negative numbers
    func testNegatives() throws {
        let template = "#(10)\n#(-10)"
        
        try XCTAssertEqual(parse(raw: template).scopes[0][0].description, "int(10)")
        try XCTAssertEqual(render(raw: template), "10\n-10")
    }

    /// Validate parse resolution of evaluable expressions
    func testComplexParameters() throws {
        let input = """
        #(index-5)
        #(10-5)
        #(10 - 5)
        #(-5)
        """

        let syntax = """
        0: [$:index - int(5)]
        1: raw(LeafBuffer: 7B)
        """

        try XCTAssertEqual(parse(raw: input).terse, syntax)
        try XCTAssertEqual(render(raw: input, ["index": 10]), "5\n5\n5\n-5")
    }

    /// Validate parse resolution of negative numbers
    func testOperandGrouping() throws {
        let template = """
        #(!true&&!false)
        #((!true) || (!false))
        #((true) && (!false))
        #((!true) || (false))
        #(!true || !false)
        #(true)
        #(-5 + 10 - 20 / 2 + 9 * -3 == 90 / 3 + 0b010 * -0xA)
        """

        let syntax = """
        0: bool(false)
        1: raw(LeafBuffer: 32B)
        """

        let expectation = """
        false
        true
        true
        false
        true
        true
        false
        """

        try XCTAssertEqual(parse(raw: template).terse, syntax)
        try XCTAssertEqual(render(raw: template), expectation)
    }
    
    func testEscapedStringParam() throws {
        let template = #"""
        #("A string \"with quoted\" portions")"
        """#
        if case .param(.literal(.string(let result))) = try lex(raw: template)[3].token {
            XCTAssertEqual(result, #"A string "with quoted" portions"#)
        } else { XCTFail() }
    }
    
    func testASTInfo() throws {
        let template = """
        #inline("template")
        #inline("template", as: leaf)
        #inline("template", as: raw)
        #define(aBlock = variable)
        #define(anotherBlock):
            #(let aDeclaredVariable = variable * 2)
            #(aDeclaredVariable)
        #enddefine
        #evaluate(aBlock)
        #evaluate(anotherBlock)
        #(aThirdVariable)
        #($scope.scoped)
        """
        
        let astInfo = try parse(raw: template).info
        
        XCTAssertTrue(astInfo.requiredASTs == ["template"])
        XCTAssertTrue(astInfo.requiredRaws == ["template"])
        XCTAssertTrue(astInfo.requiredVars == ["variable", "aThirdVariable", "$scope.scoped"])
        XCTAssertTrue(!astInfo.requiredVars.contains("aDeclaredVariable"))
        XCTAssertTrue(astInfo.stackDepths.overallMax == 2)
    }
    
    func testSmallBugs() throws {
        struct TakesNilParam: LeafFunction, Invariant, BoolReturn {
            static var callSignature: [LeafCallParameter] {[.string(labeled: nil, optional: true)]}
            func evaluate(_ params: LeafCallValues) -> LeafData {
                .bool(params[0].string == nil)
            }
        }
        
        LeafConfiguration.entities.use(TakesNilParam(), asFunction: "takesNil")
        
        let template = """
        #(5 >= 5)
        #(5 >= 4)
        #(4 >= 5)
        #(nonExistantVariable ? true : false)
        #(nonExistantVariable == nil)
        #(nilVariable == nil)
        #takesNil(nil)
        """
        
        let expected = """
        true
        true
        false
        false
        true
        true
        true
        """
        
        try XCTAssertEqual(render(raw: template,
                                  ["nilVariable": .string(nil)],
                                  options: [.missingVariableThrows(false)]),
                           expected)
        
        try XCTAssertThrowsError(render(raw: template,
                                        ["nilVariable": .string(nil)],
                                        options: [.missingVariableThrows(true)])) {
            XCTAssert(($0 as! LeafError).description
                        .contains("[self.nonExistantVariable] variable(s) missing"),
                      $0.localizedDescription)
        }
    }
    
    func testVarPassing() throws {
        files["a"] = "#(title)"
        files["b"] = #"#let(title = "Hello")#inline("a")"#
        
        try XCTAssertEqual(render("b"), "Hello")
    }
}
