import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class LKParserTests: LeafTestClass {
    func testParseAndInline() throws {
        let sampleTemplate = """
        #define(aBlock):
            Hello #(name)!
        #enddefine

        #export(anotherBlock):
            Hello #(name)!
        #endexport

        #inline("template1")
        #inline("template2", as: leaf)
        #inline("file1", as: raw)

        #evaluate(aBlock)
        #import(aBlock)

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
        #repeat(while: self.name != nil): Do something at least once #endrepeat
        """

        let template2 = """
        #evaluate(aBlock ?? "aBlock is not defined")
        """

        var firstAST = try parse(sampleTemplate, name: "sampleTemplate")
        print(firstAST.formatted)

        let secondAST = try parse(template2, name: "template2")
        print(secondAST.formatted)

        let file1 = ByteBufferAllocator().buffer(string: "An inlined raw file")

        firstAST.inline(ast: secondAST)
        firstAST.inline(raws: ["template2" : file1])
        print(firstAST.formatted)
    }
    
    func testLooping() throws {
        let sample = """
        #(var x = 10)
        #while(x > 0):
        #for(i in x):.#endfor#(x -= 2)#endwhile
        #while(x <= 10):
        #(x += 2)#for(i in x):.#endfor#endwhile
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

        let output = try render(sample)
        XCTAssertEqual(output, expected)
    }
    
    func testSerialize() throws {
        let sample = """
        Count self: #(self.count())
        Count "name": #(name.count())
        Print "name": #(name)
        Lowercase "name" as method: #(name.lowercased())
        Uppercase explicit "name": #(self.name.uppercased())
        Validate prefix: #(self.name.hasPrefix("Mr"))
        Does aDict["one"] == 2.0: #if(aDict["one"] == 2.0):Yup#else:Nope#endif
        What's in aDict.three[0]: #(aDict.three[0])
        What's in aDict.three[3]: #(aDict.three[3] ? "Something" : "Nonexistant")
        Does aDict contain 1: #(aDict.contains(1))
        Does aDict exist: #(aDict ? "Dictionary Exists" : "No it doesn't")
        Ternary print when aDict.count == 3: #(aDict.count() == 3 ? "Three elements!" : "Wrong count")
        Discard for loop:#for(_ in self): .discard.#endfor
        Value for loop:#for(value in self): .value.#endfor
        Key and Value for loop:
        #for((key, value) in self):.key&value. ["#(key)": #(value)]
        #endfor
        """
        
        let expected = """
        Count self: 2
        Count "name": 9
        Print "name": Mr. MagOO
        Lowercase "name" as method: mr. magoo
        Uppercase explicit "name": MR. MAGOO
        Validate prefix: true
        Does aDict["one"] == 2.0: Nope
        What's in aDict.three[0]: five
        What's in aDict.three[3]: Nonexistant
        Does aDict contain 1: true
        Does aDict exist: Dictionary Exists
        Ternary print when aDict.count == 3: Three elements!
        Discard for loop: .discard. .discard.
        Value for loop: .value. .value.
        Key and Value for loop:
        .key&value. ["aDict": ["one": 1, "three": [five, ten], "two": 2.0]]
        .key&value. ["name": Mr. MagOO]
        
        """

        let context: [String: LeafData] = [
            "name"  : "Mr. MagOO",
            "aDict" : ["one": 1, "two": 2.0, "three": ["five", "ten"]]
        ]
        
        
        let start = Date()
        let sampleAST = try parse(sample)
        let parsedTime = start.distance(to: Date())

        print(sampleAST.formatted)
        let serializer = LKSerializer(sampleAST, .init(context), ByteBuffer.self)
        var block = ByteBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)
        let result = serializer.serialize(&block)
        switch result {
            case .success(let duration):
                XCTAssertEqual(block.contents, expected)
                print("    Parse: " + parsedTime.formatSeconds())
                print("Serialize: " + duration.formatSeconds())
            case .failure(let error):
                print(error.localizedDescription)
        }
    }
    
    func testEscaping() throws {
        let sample = """
        #(payload.escapeHTML())
        """
        let expected = """
        &lt;script&gt;&quot;Don&apos;t let me get out &amp; do some serious damage&quot;&lt;/script&gt;
        """
        let context: [String: LeafData] = [
            "payload"  : """
            <script>"Don't let me get out & do some serious damage"</script>
            """
        ]
        try XCTAssertEqual(render(name: "test", sample, .init(context)) , expected)
    }

    func testVsComplex() throws {
        let loopCount = 10
        let context: [String: LeafData] = [
            "name"  : "vapor",
            "skills" : Array.init(repeating: ["bool": true.leafData, "string": "a;sldfkj".leafData,"int": 100.leafData], count: loopCount).leafData,
            "me": "LOGAN"
        ]

        let sample = """
        hello, #(name)!
        #for(index in skills):
        #(skills[index])
        #endfor
        """

        var total = 0.0
        var leafBuffer: ByteBuffer = ByteBufferAllocator().buffer(capacity: 0)
        for x in 1...10 {
            var lap = Date()
            var sampleParse = try! LKParser(.searchKey("s"), lex(sample))
            let sampleAST = try! sampleParse.parse()
            print("    Parse: " + lap.distance(to: Date()).formatSeconds())
            lap = Date()
            let serializer = LKSerializer(sampleAST, .init(context), ByteBuffer.self)
            var block = ByteBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)
            print("    Setup: " + lap.distance(to: Date()).formatSeconds())
            let result = serializer.serialize(&block)
            switch result {
                case .success(let duration) : print("Serialize: " + duration.formatSeconds())
                                              total += duration
                case .failure(let error)    : print(error.localizedDescription)
            }
            if x == 10 { leafBuffer.append(&block) }
        }

//        let lap = Date()
//        var buffered = ByteBufferAllocator().buffer(capacity: 0)
//        buffered.append("hello, \(context["name"]!.string!)!\n".leafData)
//        for index in context["skills"]!.array!.indices {
//            buffered.append(context["skills"]!.array![index])
//            buffered.append("\n\n".leafData)
//        }
//        let rawSwift = lap.distance(to: Date())
//
//        XCTAssert(buffered.writerIndex == leafBuffer.writerIndex, "Raw Swift & Leaf Output Don't Match")

//        print("Indices - Leaf: \(leafBuffer.writerIndex) / Raw: \(buffered.writerIndex)")

//        print("Raw Swift unwrap and concat: \(rawSwift.formatSeconds)")

        print("Average serialize duration: \((total / 10.0).formatSeconds())")
//        print(String(format: "Overhead: %.2f%%", 1000.0 * rawSwift / total))
//        print(String("Difference per loop: " + (((total/10.0) - rawSwift)/Double(loopCount)).formatSeconds))
        print("Output size: \(leafBuffer.readableBytes.formatBytes())")
        print(leafBuffer.string)
    }

    func testEvalAndComments() throws {
        let sample = """
        #define(block):
        Is #(self["me"] + " " + name)?: #($context.me == name)
        #enddefine
        #define(parameterEvaluable, ["tdotclare", "Teague"])
        
        #evaluate(parameterEvaluable)
        #evaluate(block)
        #(# here's a comment #)
        #("And a comment" # On...
                            multiple...
                            lines. # )

        #define(block, nil)
        Defaulted : #evaluate(block ?? "Block doesn't exist")
        No default: #evaluate(block)
        """

        let context: [String: LeafData] = ["name": "Teague", "me": "Teague"]
        
        let sampleAST = try parse(sample)
        print(sampleAST.formatted)
        let serializer = LKSerializer(sampleAST, .init(context), ByteBuffer.self)
        var block = ByteBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)

        let result = serializer.serialize(&block)
        switch result {
            case .success        : print(block.contents)
            case .failure(let e) : print(e.localizedDescription)
        }
    }

    func testNestedForAndTernary() throws {
        let sample = """
        #for(index in 10):
        #(index): #for((pos, char) in "Hey Teague"):#(pos != index ? char : "_")#endfor#endfor
        """

        let sampleAST = try parse(sample)
        print(sampleAST.formatted)
        
        let serializer = LKSerializer(sampleAST, [:], ByteBuffer.self)
        var block = ByteBuffer.instantiate(size: sampleAST.underestimatedSize, encoding: .utf8)

        let result = serializer.serialize(&block)
        switch result {
            case .success        : print(block.contents)
            case .failure(let e) : print(e.localizedDescription)
        }
    }
  
    func testAssignmentAndCollections() throws {
        let input = """
        #(var x)
        #(var y = 5 + 10)
        #(x = [])#(x)
        #(x = [:])#(x)
        #(x = [x, 5])#(x)
        #(x = ["x": x, "y": y])#(x)
        #(x.x[0])
        #(self.x)
        """

        let parseExpected = """
         0: [var $:x void()?]
         2: [var $:y int(15)]
         4: [$:x = array(count: 0)]
         5: $:x
         7: [$:x = dictionary(count: 0)]
         8: $:x
        10: [$:x = array[$:x, int(5)]]
        11: $:x
        13: [$:x = dictionary["x": variable($:x), "y": variable($:y)]]
        14: $:x
        16: [$:x.x [] int(0)]
        18: $context:x
        """

        let parsedAST = try! parse(input)
        XCTAssertEqual(parsedAST.terse, parseExpected)
        
        let serializeExpected = """
        

        []
        [:]
        [[:], 5]
        ["x": [[:], 5], "y": 15]
        [:]
        Hi tdotclare
        """
        
        let serializer = LKSerializer(parsedAST, ["x": "Hi tdotclare"], ByteBuffer.self)
        var block = ByteBuffer.instantiate(size: parsedAST.underestimatedSize, encoding: .utf8)
        let result = serializer.serialize(&block)
        switch result {
            case .success        : XCTAssertEqual(block.contents, serializeExpected)
            case .failure(let e) : XCTFail(e.localizedDescription)
        }
    }
    
    func testMutatingMethods() throws {
        let input = """
        #(var x = "t")
        #(x.append("dotclare"))
        #(var y = x)#(x)
        #while(y.popLast()):
        #(y)#endwhile
        """

        let parseExpected = """
        0: [var $:x string(t)]
        2: append($:x, string(dotclare))
        4: [var $:y $:x]
        5: $:x
        7: while(popLast($:y)):
        8: scope(table: 1)
           1: $:y
        """

        let parsedAST = try parse(input)
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
        
        let serializer = LKSerializer(parsedAST, [:], ByteBuffer.self)
        var block = ByteBuffer.instantiate(size: parsedAST.underestimatedSize, encoding: .utf8)
        let result = serializer.serialize(&block)
        switch result {
            case .success        : XCTAssertEqual(block.contents, serializeExpected)
            case .failure(let e) : XCTFail(e.localizedDescription)
        }
    }
    
    func _testResumingSerialize() throws {
        var testFiles = TestFiles()
        testFiles.files["/sample.leaf"] = """
            hello, #(name)!
            #for(index in skills):
            #(skills[index])
            #endfor
            """

        let renderer = TestRenderer(sources: .singleSource(testFiles))
        
        let loopCount = 10_000
        let context: [String: LeafData] = [
            "name"  : "vapor",
            "skills" : Array.init(repeating: ["bool": true.leafData, "string": "a;sldfkj".leafData,"int": 100.leafData], count: loopCount).leafData,
            "me": "LOGAN"
        ]
        
        _ = try renderer.render(path: "sample", context: .init(context)).always {
            switch $0 {
                case .failure(let e): XCTFail((e as! LeafError).localizedDescription)
                case .success(let b): XCTAssertTrue(b.readableBytes == 0, "\(b.readableBytes.formatBytes())")
            }
        }.wait()
    }
    
    func testVarStyle() throws {
        let scoped = """
        #(var x = 5)
        #(x)
        #if(x == 5):
            #(var x = "A String")
            #(x.append(" and more string"))
            #(x)
        #endif
        #(x -= 5)
        #(x)
        """
        
        let validConstant = """
        #(let x)
        #(x = "A String")
        #(x)
        """
        
        let invalidConstant = """
        #(let x = "A String")
        #(x.append(" and more string"))
        #(x)
        """
        
        let overloadScopeVariable = """
        #for(index in 10):
        #(var i = index + 1)#(i)
        #endfor
        """
        
        let x = try render(scoped)
        XCTAssert(x.contains("String and more"))
        XCTAssert(x.contains("5"))
        let y = try render(validConstant)
        XCTAssert(y.contains("A String"))
        do { try _ = render(invalidConstant); XCTFail("Should have thrown") }
        catch { XCTAssert((error as! LeafError).description.contains("x is constant; can't call mutating method `append()`")) }
        let z = try render(overloadScopeVariable)
        XCTAssert(z.contains("10"))        
    }
}

