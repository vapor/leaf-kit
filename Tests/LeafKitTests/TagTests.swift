@testable import LeafKit
import XCTest

final class TagTests: XCTestCase {
    func testWithHTMLEntities() throws {
        let template = """
        #(name)
        """
        let expected = """
        &lt;h1&gt;Alex&lt;/h1&gt;&quot;&#39;
        """
        try XCTAssertEqual(render(template, ["name": "<h1>Alex</h1>\"\'"]), expected)
    }

    func testUnsafeTag() throws {
        let template = """
        #unsafeHTML(name)
        """
        let expected = """
        <h1>Alex</h1>
        """
        try XCTAssertEqual(render(template, ["name": "<h1>Alex</h1>"]), expected)
    }

    func testUnsafeTagInteger() throws {
        let template = """
        #unsafeHTML(value)
        """
        let expected = """
        12345
        """
        try XCTAssertEqual(render(template, ["value": 12345]), expected)
    }

    func testLowercaseTag() throws {
        let template = """
        #lowercased(name)
        """
        let expected = """
        &lt;tim&gt;
        """
        try XCTAssertEqual(render(template, ["name": "<Tim>"]), expected)
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

    func testUppercaseTagWithHTML() throws {
        let template = """
        #uppercased(name)
        """
        let expected = """
        &lt;H1&gt;TIM&lt;/H1&gt;
        """
        try XCTAssertEqual(render(template, ["name": "<h1>Tim</h1>"]), expected)
    }

    func testCapitalizedTag() throws {
        let template = """
        #capitalized(name)
        """
        let expected = """
        Tim
        """
        try XCTAssertEqual(render(template, ["name": "tim"]), expected)
    }

    func testCapitalizedTagWithHTML() throws {
        let template = """
        #capitalized(name)
        """
        let expected = """
        &lt;H1&gt;Tim&lt;/H1&gt;
        """
        try XCTAssertEqual(render(template, ["name": "<h1>tim</h1>"]), expected)
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
    
    func testIsEmpty() throws {
        let template = """
        #if(isEmpty(emptyString)):
            This is an empty string.
        #endif
        """

        let expected = """

            This is an empty string.

        """
        try XCTAssertEqual(render(template, ["emptyString": ""]), expected)
    }
    
    func testIsEmptyFalseCase() throws {
        let template = """
        #if(isEmpty(nonEmptyString)):
            This is an empty string.
        #else:
            This is not an empty string.
        #endif
        """

        let expected = """

            This is not an empty string.

        """
        try XCTAssertEqual(render(template, ["nonEmptyString": "I'm not empty."]), expected)
    }

    func testContainsTagWithHTML() throws {
        let template = """
        #if(contains(core, "<h1>Tanner</h1>")):
            Tanner is in the core team!
        #endif
        """

        let expected = """

            Tanner is in the core team!

        """
        try XCTAssertEqual(render(template, ["core": ["<h1>Tanner</h1>", "Logan", "Gwynne", "Siemen", "Tim"]]), expected)
    }


    func testDate() throws {
        let template = """
        The date is #date(now)
        """

        let expected = """
        The date is 2020-11-09T14:30:00
        """

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        let date = formatter.date(from: "2020-11-09T14:30:00")!
        let now = Int(date.timeIntervalSince1970)

        try XCTAssertEqual(render(template, ["now": .int(now)]), expected)
    }

    func testDateWithCustomFormat() throws {
        let template = """
        The date is #date(now, "yyyy-MM-dd")
        """

        let expected = """
        The date is 2020-11-09
        """

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .init(secondsFromGMT: 0)
        let date = formatter.date(from: "2020-11-09T14:30:00")!
        let now = Int(date.timeIntervalSince1970)

        try XCTAssertEqual(render(template, ["now": .int(now)]), expected)
    }

    func testDateWithCustomFormatWithHTML() throws {
        let template = """
        The date is #date(now, "<yyyy-MM-dd>")
        """

        let expected = """
        The date is &lt;2020-11-09&gt;
        """

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .init(secondsFromGMT: 0)
        let date = formatter.date(from: "2020-11-09T14:30:00")!
        let now = Int(date.timeIntervalSince1970)

        try XCTAssertEqual(render(template, ["now": .int(now)]), expected)
    }

    func testDateWithCustomFormatAndTimeZone() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .init(secondsFromGMT: 0)
        let date = formatter.date(from: "2020-11-09T14:30:00")!
        let now = Int(date.timeIntervalSince1970)

        let templateNewYork = """
        The date is #date(now, "yyyy-MM-dd'T'HH:mm", "America/New_York")
        """

        let expectedNewYork = """
        The date is 2020-11-09T09:30
        """
        
        try XCTAssertEqual(render(templateNewYork, ["now": .int(now)]), expectedNewYork)
        
        let templateCalifornia = """
        The date is #date(now, "yyyy-MM-dd'T'HH:mm", "America/Los_Angeles")
        """

        let expectedCalifornia = """
        The date is 2020-11-09T06:30
        """
        
        try XCTAssertEqual(render(templateCalifornia, ["now": .int(now)]), expectedCalifornia)
    }

    func testDumpContext() throws {
        let data: [String: LeafData] = ["value": 12345]
        let template = """
        dumpContext should output debug description #dumpContext
        """

        let expected = """
        dumpContext should output debug description [value: "12345"]
        """

        try XCTAssertEqual(render(template, data), expected)
    }

    #if !os(Android)
    func testPerformance() throws {
        let template = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#(title)</title>
          </head>
          <body>
            <h1>#(title)</h1>
            <p>#(paragraph1)</p>
            <p>#lowercased(paragraph2)</p>
            <p>#uppercased(paragraph3)</p>
            <p>#(someValue)</p>

            <ul>
                #for(item in list):
                    <li>#(item)</li>
                #endfor
            </ul>
          </body>
        </html>
        """

        func numberDescriptions(count: Int) -> String {
            (0..<count).map(\.description).joined(separator: " ")
        }

        let context: [String: LeafData] = [
            "title": .string(numberDescriptions(count: 2000)),
            "paragraph1": .string(numberDescriptions(count: 1000)),
            "paragraph2": .string(numberDescriptions(count: 1) + "<h1>asdf</h1>"),
            "paragraph3": .string(numberDescriptions(count: 300)),
            "someValue": .double(123123.321),
            "list": .array(
                (0..<1000).map { _ in .string(numberDescriptions(count: 1000)) }
            )
        ]

        measure {
            do {
                _ = try render(template, context)
            } catch {
                fatalError("render failed: \(error)")
            }
        }
    }
    #endif
}
