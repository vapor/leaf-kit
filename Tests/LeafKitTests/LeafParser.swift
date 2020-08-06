import XCTest
import NIOConcurrencyHelpers
@testable import LeafKit

final class Leaf4ParserTests: LeafTestClass {
    func testParser() throws {
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
        #extend("template3")

        #(name.hasPrefix("Mr"))

        #if(lowercased(((name == "admin"))) == "welcome"):
            #(0b0101010 + 0o052 + 42 - 0_042 * 0x02A / self.meaning - 0_042.0 + 0x02A.0)
            #if(variable[0] ?? true): subscripting & coalescing #endif
        #elseif(false):
            Abracadabra
            #(one)
        #else:
            Tralala
        #endif

        #(if(name == nil, true))
        #for(_ in collection): something #endfor
        #for(value in collection): something #endfor
        #for((key, value) in collection): something #endfor
        #while($request.name.lowercased() == "aValue"): Maybe do something #endwhile
        #repeat(while: self.name != nil): Do something at least once #endrepeat
        """
        
        let template2 = """
        #evaluate(aBlock ?? "aBlock is not defined")
        """
       
        var tokens = try lex(sampleTemplate)
        var parser = Leaf4Parser("SampleTemplate", tokens)
        var firstAST = try parser.parse()
        print(firstAST.formatted)
        
        tokens = try lex(template2)
        parser = Leaf4Parser("template2", tokens)
        let secondAST = try parser.parse()
        print(secondAST.summary)
        
        let file1 = ByteBufferAllocator().buffer(string: "An inlined raw file")
        
        firstAST.inline(ast: secondAST)
        firstAST.inline(raws: ["file1" : file1])
        print(firstAST.formatted)
        
        let sample = """
        #count(Dictionary(self))
        #count(name)
        #(name)
        #(name.lowercased())
        #lowercased(name)
        #(self.name.uppercased())
        #hasPrefix(self.name, "Mr")
        #for(_ in self): ....
        #for(value in self): ...
        #for((key, value) in self): ...
            [#(key) : #(value)]
        #endfor
        #if(aDict["one"] == 2.0): Ooop! #endif
        #(aDict.three[0])
        """
        
        let context: [String: LeafData] = [
            "name"  : "Mr. MagOO",
            "aDict" : ["one": 1, "two": 2.0, "three": ["five", "ten"]]
        ]
        let start = Date()
        var sampleParse = try! Leaf4Parser("s", lex(sample))
        let sampleAST = try! sampleParse.parse()
        let parsedTime = start.distance(to: Date())
        
        print(sampleAST.formatted)
        var serializer = Leaf4Serializer(ast: sampleAST, context: context)
        let buffer = ByteBufferAllocator().buffer(capacity: Int(sampleAST.underestimatedSize))
        var block = ByteBuffer.instantiate(data: buffer, encoding: .utf8)
        
        let result = serializer.serialize(buffer: &block)
        switch result {
            case .success(let duration):
                print(block.contents)
                print("    Parse: " + parsedTime.formatSeconds)
                print("Serialize: " + duration.formatSeconds)
            case .failure(let error):
                print(error.localizedDescription)
        }
    }
    
    
    func testVsComplex() throws {
        let loopCount = 100
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
            var sampleParse = try! Leaf4Parser("s", lex(sample))
            let sampleAST = try! sampleParse.parse()
            print("    Parse: " + lap.distance(to: Date()).formatSeconds)
            lap = Date()
            var serializer = Leaf4Serializer(ast: sampleAST, context: context)
            let buffer = ByteBufferAllocator().buffer(capacity: Int(sampleAST.underestimatedSize))
            var block = ByteBuffer.instantiate(data: buffer, encoding: .utf8)
            print("    Setup: " + lap.distance(to: Date()).formatSeconds)
            let result = serializer.serialize(buffer: &block)
            switch result {
                case .success(let duration) : print("Serialize: " + duration.formatSeconds)
                                              total += duration
                case .failure(let error)    : print(error.localizedDescription)
            }
            if x == 10 { try! leafBuffer.append(&block) }
        }

        let lap = Date()
        var buffered = ByteBufferAllocator().buffer(capacity: 0)
        buffered.append("hello, \(context["name"]!.string!)!\n".leafData)
        for index in context["skills"]!.array!.indices {
            buffered.append(context["skills"]!.array![index])
            buffered.append("\n\n".leafData)
        }
        let rawSwift = lap.distance(to: Date())
        
        XCTAssert(buffered.writerIndex == leafBuffer.writerIndex, "Raw Swift & Leaf Output Don't Match")
        
        print("Indices - Leaf: \(leafBuffer.writerIndex) / Raw: \(buffered.writerIndex)")
        
        print("Raw Swift unwrap and concat: \(rawSwift.formatSeconds)")
        
        print("Average serialize duration: \((total / 10.0).formatSeconds)")
        print(String(format: "Overhead: %.2f%%", 1000.0 * rawSwift / total))
        print(String("Difference per loop: " + (((total/10.0) - rawSwift)/Double(loopCount)).formatSeconds))
        print("Output size: \(leafBuffer.readableBytes.formatBytes)")
    }
    
    func testEval() throws {
        let sample = """
        #define(block):
        Is #(self["me"] + " " + name)?: #($context.me == name)
        #enddefine

        #evaluate(block)
        #(# here's a comment #)
        #("And a comment" # On...
                            multiple...
                            lines. # )

        #define(block, nil)
        Defaulted : #evaluate(block ?? "Block doesn't exist")
        No default: #evaluate(block)
        """
        
        let context: [String: LeafData] = [
            "name": "Teague",
            "me": "Teague"
        ]
        var sampleParse: Leaf4Parser
        do {
            sampleParse = try Leaf4Parser("s", lex(sample))
        } catch let e as LeafError { throw e.localizedDescription }
        let sampleAST = try! sampleParse.parse()
        print(sampleAST.formatted)
        var serializer = Leaf4Serializer(ast: sampleAST, context: context)
        let buffer = ByteBufferAllocator().buffer(capacity: Int(sampleAST.underestimatedSize))
        var block = ByteBuffer.instantiate(data: buffer, encoding: .utf8)
        
        let result = serializer.serialize(buffer: &block)
        switch result {
            case .success:
                print(block.contents)
            case .failure(let error):
                print(error.localizedDescription)
        }
    }
    
    func testForAndIf() throws {
        let sample = """
        #for(index in 10):
        #(index): #for((pos, char) in "Hey Teague"):#if(pos != index):#(char)#else:_#endif#endfor#endfor
        """
        
        let context: [String: LeafData] = [:]
        var sampleParse = try! Leaf4Parser("s", lex(sample))
        let sampleAST = try! sampleParse.parse()
        print(sampleAST.formatted)
        var serializer = Leaf4Serializer(ast: sampleAST, context: context)
        let buffer = ByteBufferAllocator().buffer(capacity: Int(sampleAST.underestimatedSize))
        var block = ByteBuffer.instantiate(data: buffer, encoding: .utf8)
        
        let result = serializer.serialize(buffer: &block)
        switch result {
            case .success:        print(block.contents)
            case .failure(let e): print(e.localizedDescription)
        }
    }
}

