import XCTest
@testable import LeafKit

final class SerializerTests: LeafTestClass {
    func testComplex() {
        
        let name = LeafData(.string("vapor"))
        let me = LeafData(.string("LOGAN"))
        let skills = Array.init(repeating: ["bool": true.leafData, "string": "a;sldfkj".leafData,"int": 100.leafData], count: 10).leafData
        let context = ["name": name, "skills": skills, "me": me]
        
        let input = """
        hello, #(name)!
        #for(skill in skills):
        #(skill)
        #endfor
        """
        
        var total = 0.0
        
        for _ in 1...10 {
            var lap = Date()
            print("    Parse: " + lap.distance(to: Date()).formatSeconds)
            lap = Date()
            let _ = try! render(name: "sample", input, context)
            let duration = lap.distance(to: Date())
            print("Serialize: " + duration.formatSeconds)
            total += duration
        }
        
        print("Average serialize duration: \((total / 10.0).formatSeconds)")
    }

    func testNestedKeyPathLoop() throws {
        let input = """
        #for(person in people):
        hello #(person.name)
        #for(skill in person.skills):
        you're pretty good at #(skill)
        #endfor
        #endfor
        """

        let people = LeafData(.array([
            LeafData(.dictionary([
                "name": "LOGAN",
                "skills": LeafData(.array([
                    "running",
                    "walking"
                ]))
            ]))
        ]))

        let result = try! render(name: "test", input, ["people": people])

        XCTAssertEqual(result, """

        hello LOGAN

        you're pretty good at running

        you're pretty good at walking

        """)
    }
}
