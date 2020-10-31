import XCTest
@testable import LeafKit

final class LeafSerializerTests: MemoryRendererTestCase {
    func testComplex() throws {
        let skill: LeafData = .dictionary(["bool": true, "string": "a;sldfkj", "int": 100])
        let context: LKRContext = ["name": "vapor", "skills": .array(.init(repeating: skill, count: 10)), "me": "LOGAN"]

        files["template"] = """
        hello, #(name)!
        #for(skill in skills):
        #(skill)
        #endfor
        """

        var timer = Stopwatch()

        for _ in 1...10 {
            print("    Parse: \(timer.lap())")
            try render("template", context)
            print("Serialize: \(timer.lap(accumulate: true))")
        }

        print("Average serialize duration: \(timer.average)")
    }

    func testNestedKeyPathLoop() throws {
        files["template"] = """
        #for(person in people):
        hello #(person.name)
        #for(skill in person.skills):
        you're pretty good at #(skill)
        #endfor
        #endfor
        """

        let people: LeafData = .array([
            .dictionary([
                "name": "LOGAN",
                "skills": .array(["running", "walking"])
            ])
        ])

        try XCTAssertEqual(render("template", ["people": people]), """
        hello LOGAN
        you're pretty good at running
        you're pretty good at walking
        
        """)
    }
        
    func _testResumingSerialize() throws {
        /// Not valid test currently
        files["template"] = """
        hello, #(name)!
        #for(index in skills):
        #(skills[index])
        #endfor
        """
        
        let item: LeafData = .dictionary(["bool": true, "string": "a;sldfkj", "int": 100])
        let context: LKRContext = [
            "name"  : "vapor",
            "skills" : .array(.init(repeating: item, count: 10_000)),
            "me": "LOGAN"
        ]
        
        let buffer = try renderBuffer("sample", context).wait()
        XCTAssert(buffer.readableBytes == 0, buffer.readableBytes.formatBytes())
    }
}
