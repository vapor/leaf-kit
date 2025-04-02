import Testing

@testable import LeafKit

@Suite
struct SerializerTests {
    func testNestedKeyPathLoop() throws {
        let input = """
            #for(person in people):
            hello #(person.name)
            #for(skill in person.skills):
            you're pretty good at #(skill)
            #endfor
            #endfor
            """

        let syntax = try parse(input)
        let people = LeafData(
            .array([
                LeafData(
                    .dictionary([
                        "name": "LOGAN",
                        "skills": LeafData(.array(["running", "walking"])),
                    ]))
            ]))

        var serializer = LeafSerializer(ast: syntax, ignoreUnfoundImports: false)
        var serialized = try serializer.serialize(context: ["people": people])
        let str = (serialized.readString(length: serialized.readableBytes) ?? "<err>")

        #expect(
            str == """

                hello LOGAN

                you're pretty good at running

                you're pretty good at walking


                """)
    }

    func testInvalidNestedKeyPathLoop() throws {
        let input = """
            #for(person in people):
            hello #(person.name)
            #for(skill in person.profile.skills):
            you're pretty good at #(skill)
            #endfor
            #endfor
            """

        let syntax = try parse(input)
        let people = LeafData(
            .array([
                LeafData(
                    .dictionary([
                        "name": "LOGAN",
                        "skills": LeafData(.array(["running", "walking"])),
                    ]))
            ]))

        var serializer = LeafSerializer(ast: syntax, ignoreUnfoundImports: false)

        let error = #expect(throws: LeafError.self) { try serializer.serialize(context: ["people": people]) }
        #expect(error.localizedDescription.contains("expected dictionary at key: person.profile"))
    }
}
