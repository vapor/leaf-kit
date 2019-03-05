import XCTest
@testable import LeafKit

final class SerializerTests: XCTestCase {
    func testComplex() throws {
        let input = """
        hello, #(name)!
        #for(skill in skills):
        you're pretty good at #(skill)
        #endfor

        #if(false): don't show
        #elseif(true):
        it works!
        #endif

        #if(lowercased(me) == "logan"):
        expression resolution worked!!
        #endif
        """
        
        let syntax = try! altParse(input)
        let name = TemplateData(.string("vapor"))
        
        let me = TemplateData(.string("LOGAN"))
        let running = TemplateData(.string("running"))
        let walking = TemplateData(.string("walking"))
        let skills = TemplateData(.array([running, walking]))
        var serializer = LeafSerializer(ast: syntax, context: ["name": name, "skills": skills, "me": me])
        var serialized = try serializer.serialize()
        let str = serialized.readString(length: serialized.readableBytes) ?? "<err>"
        print(str)
        print()
//        let syntax = try! altParse(input)
//        let output = syntax.map { $0.description } .joined(separator: "\n")
//        XCTAssertEqual(output, expectation)
    }
}
