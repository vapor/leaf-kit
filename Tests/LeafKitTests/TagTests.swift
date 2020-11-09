import XCTest
@testable import LeafKit

class TagTests: XCTestCase {
    func testLowercaseTag() throws {
        let template = """
        #lowercased(name)
        """
        let expected = """
        tim
        """
        try XCTAssertEqual(render(template, ["name": "Tim"]), expected)
    }

    func testLowercaseTagWithAllCaps() throws {
        let template = """
        #lowercased(name)
        """
        let expected = """
        tim
        """
        try XCTAssertEqual(render(template, ["name": "TIM"]), expected)
    }

    func testUppercaseTag() throws {
        let template = """
        #uppercased(name)
        """
        let expected = """
        TIM
        """
        try XCTAssertEqual(render(template, ["name": "Tim"]), expected)
    }

    func testCapitalisedTag() throws {
        let template = """
        #capitalized(name)
        """
        let expected = """
        Tim
        """
        try XCTAssertEqual(render(template, ["name": "tim"]), expected)
    }

    func testCount() throws {
        let template = """
        There are #count(people) people
        """

        let expected = """
        There are 5 people
        """
        try XCTAssertEqual(render(template, ["people": ["Tanner", "Logan", "Gwynne", "Siemen", "Tim"]]), expected)
    }
}
