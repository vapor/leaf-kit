@testable import XCTLeafKit
@testable import LeafKit

final class LeafParserTests: MemoryRendererTestCase {
    func testParsingNesting() throws {
        let template = """
        #if((name.first == "admin").lowercased() == "welcome"):
        foo
        #endif
        """

        let expectation = """
        0: if([lowercased([$:name.first == string(admin)]) == string(welcome)]):
        1: raw(LeafBuffer: 5B)
        """

        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }

    func testComplex() throws {
        let template = """
        #if(foo):
        foo
        #else:
        foo
        #endif
        """

        let expectation = """
        0: if($:foo):
        1: raw(LeafBuffer: 5B)
        2: else:
        3: raw(LeafBuffer: 5B)
        """

        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }

    func testCompiler() throws {
        let template = """
        #if(sayhello):
            abc
            #for(name in names):
                hi, #(name)
            #endfor
            def
        #else:
            foo
        #endif
        """

        let expectation = """
        0: if($:sayhello):
        1: scope(table: 1)
           0: raw(LeafBuffer: 13B)
           1: for($:names):
           2: scope(table: 2)
              0: raw(LeafBuffer: 13B)
              1: $:name
              2: raw(LeafBuffer: 5B)
           3: raw(LeafBuffer: 9B)
        2: else:
        3: raw(LeafBuffer: 9B)
        """

        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }

    func testUnresolvedAST() throws {
        let template = """
        #inline("header")
        <title>#evaluate(title)</title>
        #evaluate(body)
        """

        try XCTAssertFalse(parse(raw: template).requiredFiles.isEmpty, "Unresolved template")
    }

    func testInsertResolution() throws {
        let header = """
        <h1>Hi!</h1>
        """
        
        let base = """
        #inline("header")
        <title>#evaluate(title)</title>
        #inline("header")
        """

        let preinline = """
        0: inline("header", leaf):
        1: scope(undefined)
        2: raw(LeafBuffer: 8B)
        3: evaluate(title):
        4: scope(undefined)
        5: raw(LeafBuffer: 9B)
        6: inline("header", leaf):
        7: scope(undefined)
        """

        let expectation = """
        0: inline("header", leaf):
        1: raw(LeafBuffer: 12B)
        2: raw(LeafBuffer: 8B)
        3: evaluate(title):
        4: scope(undefined)
        5: raw(LeafBuffer: 9B)
        6: inline("header", leaf):
        7: raw(LeafBuffer: 12B)
        """

        var baseAST = try parse(raw: base, name: "base")
        let headerAST = try parse(raw: header, name: "header")
        
        XCTAssertEqual(baseAST.terse, preinline)
        baseAST.inline(ast: headerAST)
        XCTAssertEqual(baseAST.terse, expectation)
    }

    func testDocumentResolveExtend() throws {
        let header = """
        <h1>#evaluate(header)</h1>
        """

        let base = """
        #inline("header")
        <title>#evaluate(title)</title>
        #evaluate(body)
        """

        let home = """
        #define(title = "Welcome")
        #define(body):
            Hello, #(name)!
        #enddefine
        #inline("base")
        """

        let expectation = """
        0: define(title):
        1: string(Welcome)
        3: define(body):
        4: scope(table: 1)
           0: raw(LeafBuffer: 12B)
           1: $:name
           2: raw(LeafBuffer: 2B)
        6: inline("base", leaf):
        7: scope(table: 2)
           0: inline("header", leaf):
           1: scope(table: 3)
              0: raw(LeafBuffer: 4B)
              1: evaluate(header):
              2: scope(undefined)
              3: raw(LeafBuffer: 5B)
           2: raw(LeafBuffer: 8B)
           3: evaluate(title):
           4: scope(undefined)
           5: raw(LeafBuffer: 9B)
           6: evaluate(body):
           7: scope(undefined)
        """

        let headerAST = try parse(raw: header, name: "header")
        var baseAST = try parse(raw: base, name: "base")
        var homeAST = try parse(raw: home, name: "home", options: [.parseWarningThrows(false)])

        baseAST.inline(ast: headerAST)
        homeAST.inline(ast: baseAST)

        XCTAssertEqual(homeAST.terse, expectation)
    }

    func testCompileExtend() throws {
        let template = """
        #define(title = "Welcome")
        #define(body):
            Hello, #(name)!
        #enddefine
        #inline("base")
        #title()
        #implictEval()
        """

        let expectation = """
         0: define(title):
         1: string(Welcome)
         3: define(body):
         4: scope(table: 1)
            0: raw(LeafBuffer: 12B)
            1: $:name
            2: raw(LeafBuffer: 2B)
         6: inline("base", leaf):
         7: scope(undefined)
         9: evaluate(title):
        10: scope(undefined)
        12: evaluate(implictEval):
        13: scope(undefined)
        """

        let ast = try parse(raw: template, options: [.parseWarningThrows(false)])
        XCTAssertEqual(ast.terse, expectation)
    }

    func testScopingAndMethods() throws {
        let template = """
        #(x + $x + $context.x + $server.x)
        #($server.baseURL.hasPrefix("www") == true)
        #(array[0] + dictionary["key"])
        #($server.domain[$request.cname])
        """

        let expectation = """
        0: [$:x + [$x + [$context:x + $server:x]]]
        2: [hasPrefix($server:baseURL, string(www)) == bool(true)]
        4: [[$:array [] int(0)] + [$:dictionary [] string(key)]]
        6: [$server:domain [] $request:cname]
        """

        try XCTAssertEqual(parse(raw: template).terse, expectation)
    }
    
    func testParseAndInline() throws {
        let sampleTemplate = """
        #define(aBlock):
            Hello #(name)!
        #enddefine

        #define(anotherBlock):
            Hello #(name)!
        #enddefine

        #inline("template1")
        #inline("template2", as: leaf)
        #inline("file1", as: raw)

        #evaluate(aBlock)
        #evaluate(aBlock)

        #(name.hasPrefix("Mr"))

        #if((name == "admin").lowercased() == "welcome"):
            #(0b0101010 + 0o052 + 42 - 0_042 * 0x02A / self.meaning - 0_042.0 + 0x02A.0)
            #if(variable[0] ?? true): subscripting & coalescing #endif
        #elseif(false):
            Abracadabra
            #(one)
        #else:
            Tralala
        #endif

        #(true)
        #for(_ in collection): something #endfor
        #for(value in collection): something #endfor
        #for((key, value) in collection): something #endfor
        #while($request.name.lowercased() == "aValue"): Maybe do something #endwhile
        """

        let template2 = #"#evaluate(aBlock ?? "aBlock is not defined")"#

        let file1 = ByteBufferAllocator().buffer(string: "An inlined raw file")
        var firstAST = try parse(raw: sampleTemplate, name: "sampleTemplate")
        let secondAST = try parse(raw: template2, name: "template2")

        firstAST.inline(ast: secondAST)
        firstAST.inline(raws: ["template2" : file1])
        
        print(firstAST.formatted)
    }
    
    func testLooping() throws {
        files["template"] = """
        #(var x = 10)
        #while(x > 0):
        #for(i in x):.#endfor

        #(x -= 2)
        #endwhile

        #while(x < 10):
        #(x += 2)
        #for(i in x):.#endfor

        #endwhile
        """
        
        let expected = """
        ..........
        ........
        ......
        ....
        ..

        ..
        ....
        ......
        ........
        ..........

        """

        try XCTAssertEqual(render("template"), expected)
    }
    
    func testSerialize() throws {
        let template = """
        Count self:
            - #(self.count())
        Count "name":
            - #(name.count())
        Print "name":
            - #(name)
        Lowercase "name" as method:
            - #(name.lowercased())
        Uppercase explicit "name":
            - #(self.name.uppercased())
        Validate prefix:
            - #(self.name.hasPrefix("Mr"))
        Does aDict["one"] == 2.0:
            - #(aDict["one"] == 2.0 ? "Yup" : "Nope")
        What's in aDict.three[0]:
            - #(aDict.three[0])
        What's in aDict.three[3]:
            - #(aDict.three[3] ? "Something" : "Nonexistant")
        Does aDict contain 1:
            - #(aDict.contains(1))
        Does aDict exist:
            - #(aDict ? "Dictionary Exists" : "No it doesn't")
        Ternary print when aDict.count == 3:
            - #(aDict.count() == 3 ? "Three elements!" : "Wrong count")
        Discard for loop:
        #for(_ in self):
            - .discard.
        #endfor
        Value for loop:
        #for(value in self):
            - .value.
        #endfor
        Key and Value for loop:
        #for((key, value) in self):
            - .key&value. "#(key)" -> #(value)
        #endfor
        """
        
        let expected = """
        Count self:
            - 2
        Count "name":
            - 9
        Print "name":
            - Mr. MagOO
        Lowercase "name" as method:
            - mr. magoo
        Uppercase explicit "name":
            - MR. MAGOO
        Validate prefix:
            - true
        Does aDict["one"] == 2.0:
            - Nope
        What's in aDict.three[0]:
            - five
        What's in aDict.three[3]:
            - Nonexistant
        Does aDict contain 1:
            - true
        Does aDict exist:
            - Dictionary Exists
        Ternary print when aDict.count == 3:
            - Three elements!
        Discard for loop:
            - .discard.
            - .discard.
        Value for loop:
            - .value.
            - .value.
        Key and Value for loop:
            - .key&value. "aDict" -> ["one": 1, "three": ["five", "ten"], "two": 2.0]
            - .key&value. "name" -> Mr. MagOO
        
        """

        let context: LKRContext = [
            "name"  : "Mr. MagOO",
            "aDict" : ["one": 1, "two": 2.0, "three": ["five", "ten"]]
        ]
        
        var timer = Stopwatch()
        let sampleAST = try parse(raw: template)
        let parsedTime = timer.lap()

        let serializer = LKSerializer(sampleAST, context, LeafBuffer.self)
        var block = LeafBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)
        let result = serializer.serialize(&block)
        switch result {
            case .success(let duration):
                print("    Parse: \(parsedTime)\nSerialize: \(duration.formatSeconds())")
                XCTAssertEqual(block.contents, expected)
            case .failure(let error): XCTFail(error.localizedDescription)
        }
    }
    
    func testEscaping() throws {
        LKConf.entities.use(StrToStrMap.escapeHTML, asFunctionAndMethod: "escapeHTML")
        
        files["template"] = "#(payload.escapeHTML())"
    
        let context: LKRContext = [ "payload": """
            <script>"Don't let me get out & do some serious damage"</script>
            """]
        
        let expected = """
        &lt;script&gt;&quot;Don&apos;t let me get out &amp; do some serious damage&quot;&lt;/script&gt;
        """
        
        try XCTAssertEqual(render("template", context) , expected)
    }

    func testVsComplex() throws {
        let loopCount = 10
        let context: LKRContext = [
            "name"  : "vapor",
            "skills" : Array.init(repeating: ["bool": true.leafData, "string": "a;sldfkj".leafData,"int": 100.leafData], count: loopCount).leafData,
            "me": "LOGAN"
        ]

        let template = """
        hello, #(name)!
        #for(index in skills):
        #(skills[index])
        #endfor
        """
        
        var leafBuffer: ByteBuffer = ByteBufferAllocator().buffer(capacity: 0)
        
        var timer = Stopwatch()
        
        for x in 1...10 {
            timer.lap()
            let sampleAST = try parse(raw: template)
            print("    Parse: \(timer.lap())")
            let serializer = LKSerializer(sampleAST, context, LeafBuffer.self)
            var block = LeafBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)
            print("    Setup: \(timer.lap()) ")
            let result = serializer.serialize(&block)
            switch result {
                case .success: print("Serialize: \(timer.lap(accumulate: true))")
                case .failure(let e): XCTFail(e.localizedDescription)
            }
            if x == 10 { leafBuffer.append(&block) }
        }
        
        print("Average serialize duration: \(timer.average)")
        print("Output size: \(leafBuffer.readableBytes.formatBytes())")
        XCTAssert(true)
    }

    func testEvalAndComments() throws {
        let template = """
        #define(block):
        Is #(self["me"] + " " + name)?: #($context.me == name)
        #enddefine
        #define(parameterEvaluable = ["tdotclare", "Teague"])
        
        #evaluate(parameterEvaluable)
        #evaluate(block)
        #(# here's a comment #)
        #("And a comment" # On...
                            multiple...
                            lines. # )

        #define(block = nil)
        Defaulted : #evaluate(block ?? "Block doesn't exist")
        No default: #evaluate(block)
        """

        let context: LKRContext = ["name": "Teague", "me": "Teague"]
        
        let sampleAST = try parse(raw: template, options: [.parseWarningThrows(false)])
        let serializer = LKSerializer(sampleAST, context, LeafBuffer.self)
        var block = LeafBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)

        let result = serializer.serialize(&block)
        switch result {
            case .success        : print(block.contents); XCTAssert(true)
            case .failure(let e) : XCTFail(e.localizedDescription)
        }
    }

    func testNestedForAndTernary() throws {
        let template = """
        #for(index in 10):
        #(index): #for((pos, char) in "Hey Teague"):#(pos != index ? char : "_")#endfor
        #endfor
        """

        let sampleAST = try parse(raw: template)
        
        let serializer = LKSerializer(sampleAST, [:], LeafBuffer.self)
        var block = LeafBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)

        let result = serializer.serialize(&block)
        switch result {
            case .success        : print(block.contents); XCTAssert(true)
            case .failure(let e) : XCTFail(e.localizedDescription)
        }
    }
  
    func testAssignmentAndCollections() throws {
        let template = """
        #(var x)
        #(var y = 5 + 10)
        #(x = [])
        #(x)
        #(x = [:])
        #(x)
        #(x = [x, 5])
        #(x)
        #(x = ["x": x, "y": y])
        #(x)
        #(x.x[0])
        #(self.x)
        """

        let parseExpected = """
         0: [var $:x void?]
         2: [var $:y int(15)]
         4: [$:x = array(count: 0)]
         6: $:x
         8: [$:x = dictionary(count: 0)]
        10: $:x
        12: [$:x = array[$:x, int(5)]]
        14: $:x
        16: [$:x = dictionary["x": variable($:x), "y": variable($:y)]]
        18: $:x
        20: [$:x.x [] int(0)]
        22: $context:x
        """

        let parsedAST = try parse(raw: template)
        XCTAssertEqual(parsedAST.terse, parseExpected)
        
        let serializeExpected = """
        []
        [:]
        [[:], 5]
        ["x": [[:], 5], "y": 15]
        [:]
        Hi tdotclare
        """
        
        let serializer = LKSerializer(parsedAST, ["x": "Hi tdotclare"], LeafBuffer.self)
        var block = LeafBuffer.instantiate(size: parsedAST.underestimatedSize, encoding: .utf8)
        let result = serializer.serialize(&block)
        switch result {
            case .success        : XCTAssertEqual(block.contents, serializeExpected)
            case .failure(let e) : XCTFail(e.localizedDescription)
        }
    }
    
    func testMutatingMethods() throws {
        let template = """
        #(var x = "t")
        #(x.append("dotclare"))
        #(var y = x)
        #(x)
        #while(y.popLast()):
        #(y)
        #endwhile
        """

        let parseExpected = """
        0: [var $:x string(t)]
        2: append($:x, string(dotclare))
        4: [var $:y $:x]
        6: $:x
        8: while(popLast($:y)):
        9: scope(table: 1)
           1: $:y
        """

        let parsedAST = try parse(raw: template)
        XCTAssertEqual(parsedAST.terse, parseExpected)
        
        let serializeExpected = """
        tdotclare
        tdotclar
        tdotcla
        tdotcl
        tdotc
        tdot
        tdo
        td
        t


        """
        
        let serializer = LKSerializer(parsedAST, [:], LeafBuffer.self)
        var block = LeafBuffer.instantiate(size: parsedAST.underestimatedSize, encoding: .utf8)
        let result = serializer.serialize(&block)
        switch result {
            case .success        : XCTAssertEqual(block.contents, serializeExpected)
            case .failure(let e) : XCTFail(e.localizedDescription)
        }
    }
    
    func testVarStyle() throws {
        files["scoped"] = """
        #(var x = 5)
        #(x)
        #if(x == 5):
            #(var x = "A String")
            #(x.append(" and more string"))
            #(x)
            #(x = [:])
        #endif
        #(x -= 5)
        #(x)
        """
        
        try XCTAssert(render("scoped").contains("String and more"))
        try XCTAssert(render("scoped").contains("5"))
        
        files["validConstant"] = """
        #(let x)
        #(x = "A String")
        #(x)
        """
        
        try XCTAssert(render("validConstant").contains("A String"))
        
        files["invalidConstant"] = """
        #(let x = "A String")
        #(x.append(" and more string"))
        #(x)
        """
        
        try LKXCAssertErrors(render("invalidConstant"), contains: "Can't mutate; `x` is constant")
                                 
        files["invalidDeclare"] = """
        #(let x)
        #(x)
        """
        
        try LKXCAssertErrors(render("invalidDeclare"), contains: "Variable `x` used before initialization")
                        
        files["overloadScopeVar"] = """
        #for(index in 10):
        #(var i = index + 1)#(i)
        #endfor
        """
        
        try XCTAssert(render("overloadScopeVar").contains("10"))
        
        files["invalidScopeAssign"] = """
        #(self.x = 10)
        #(x)
        """
        
        try LKXCAssertErrors(render("invalidScopeAssign"), contains: "Can't assign; `self.x` is constant")
    }

    func testBufferWhitespaceStripping() throws {
        files["template"] = """
        #(# A Comment #)
        #(let x = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        #for(num in x):
        #(num)
        #endfor
        """
    
        try XCTAssertEqual(render("template"), "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n")
    }
    
    func testSubscriptAssignment() throws {
        files["template"] = """
        #var(x = [1])
        #(x[0] = 10)
        #(x)
        """
        
        try LKXCAssertErrors(render("template"), contains: "Assignment via subscripted access not yet supported")
    }
    
    func testInvariantFunc() throws {
        try XCTAssertEqual(parse(raw: "#(Timestamp())").terse,
                           "0: Timestamp(string(now), string(referenceDate))")
    }
    
    func testIndirectEvalWarning() throws {
        files["A"] = "A: #(content()))"
        files["B"] = "B: #inline(\"A\")"
        files["C"] = "C: #inline(\"B\")"
        files["D"] = """
        #define(content): Block can't be param define #enddefine
        #inline("A")
        """
        
        try LKXCAssertErrors(render("A"), contains: "[content()] variable(s) missing")
        try LKXCAssertErrors(render("B"), contains: "[content()] variable(s) missing")
        try LKXCAssertErrors(render("C"), contains: "[content()] variable(s) missing")
        try LKXCAssertErrors(render("D"), contains: "`A` requires parameter semantics for `content()`")
    }
    
    func testNestedLet() throws {
        files["A"] = "#let(x = 1)#inline(\"B\")"
        files["B"] = "#let(x = x ?? 2)#(x)"
        try print(render("A"))
    }
}

