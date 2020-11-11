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

    func testContainsTag() throws {
        let template = """
        #if(contains(core, "Tanner")):
            Tanner is in the core team!
        #endif
        """

        let expected = """

            Tanner is in the core team!

        """
        try XCTAssertEqual(render(template, ["core": ["Tanner", "Logan", "Gwynne", "Siemen", "Tim"]]), expected)
    }

    func testDate() throws {
        let template = """
        The date is #date(now)
        """

        let expected = """
        The date is 2020-11-09T14:30:00
        """
        try XCTAssertEqual(render(template, ["now": 1604932200]), expected)
    }

    func testDateWithCustomFormat() throws {
        let template = """
        The date is #date(now, "yyyy-MM-dd")
        """

        let expected = """
        The date is 2020-11-09
        """
        try XCTAssertEqual(render(template, ["now": 1604932200]), expected)
    }
}
