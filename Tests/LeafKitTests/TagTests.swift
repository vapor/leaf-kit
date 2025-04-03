import Foundation
import Testing

@testable import LeafKit

@Suite
struct TagTests {
    @Test func testWithHTMLEntities() throws {
        let template = """
            #(name)
            """
        let expected = """
            &lt;h1&gt;Alex&lt;/h1&gt;&quot;&#39;
            """
        #expect(render(template, ["name": "<h1>Alex</h1>\"\'"]) == expected)
    }

    @Test func testUnsafeTag() throws {
        let template = """
            #unsafeHTML(name)
            """
        let expected = """
            <h1>Alex</h1>
            """
        #expect(render(template, ["name": "<h1>Alex</h1>"]) == expected)
    }

    @Test func testUnsafeTagInteger() throws {
        let template = """
            #unsafeHTML(value)
            """
        let expected = """
            12345
            """
        #expect(render(template, ["value": 12345]) == expected)
    }

    @Test func testLowercaseTag() throws {
        let template = """
            #lowercased(name)
            """
        let expected = """
            &lt;tim&gt;
            """
        #expect(render(template, ["name": "<Tim>"]) == expected)
    }

    @Test func testLowercaseTagWithAllCaps() throws {
        let template = """
            #lowercased(name)
            """
        let expected = """
            tim
            """
        #expect(render(template, ["name": "TIM"]) == expected)
    }

    @Test func testUppercaseTag() throws {
        let template = """
            #uppercased(name)
            """
        let expected = """
            TIM
            """
        #expect(render(template, ["name": "Tim"]) == expected)
    }

    @Test func testUppercaseTagWithHTML() throws {
        let template = """
            #uppercased(name)
            """
        let expected = """
            &lt;H1&gt;TIM&lt;/H1&gt;
            """
        #expect(render(template, ["name": "<h1>Tim</h1>"]) == expected)
    }

    @Test func testCapitalizedTag() throws {
        let template = """
            #capitalized(name)
            """
        let expected = """
            Tim
            """
        #expect(render(template, ["name": "tim"]) == expected)
    }

    @Test func testCapitalizedTagWithHTML() throws {
        let template = """
            #capitalized(name)
            """
        let expected = """
            &lt;H1&gt;Tim&lt;/H1&gt;
            """
        #expect(render(template, ["name": "<h1>tim</h1>"]) == expected)
    }

    @Test func testCount() throws {
        let template = """
            There are #count(people) people
            """

        let expected = """
            There are 5 people
            """
        #expect(render(template, ["people": ["Tanner", "Logan", "Gwynne", "Siemen", "Tim"]]) == expected)
    }

    @Test func testContainsTag() throws {
        let template = """
            #if(contains(core, "Tanner")):
                Tanner is in the core team!
            #endif
            """

        let expected = """

                Tanner is in the core team!

            """
        #expect(render(template, ["core": ["Tanner", "Logan", "Gwynne", "Siemen", "Tim"]]) == expected)
    }

    @Test func testIsEmpty() throws {
        let template = """
            #if(isEmpty(emptyString)):
                This is an empty string.
            #endif
            """

        let expected = """

                This is an empty string.

            """
        #expect(render(template, ["emptyString": ""]) == expected)
    }

    @Test func testIsEmptyFalseCase() throws {
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
        #expect(render(template, ["nonEmptyString": "I'm not empty."]) == expected)
    }

    @Test func testContainsTagWithHTML() throws {
        let template = """
            #if(contains(core, "<h1>Tanner</h1>")):
                Tanner is in the core team!
            #endif
            """

        let expected = """

                Tanner is in the core team!

            """
        #expect(render(template, ["core": ["<h1>Tanner</h1>", "Logan", "Gwynne", "Siemen", "Tim"]]) == expected)
    }

    @Test func testDate() throws {
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

        #expect(render(template, ["now": .int(now)]) == expected)
    }

    @Test func testDateWithCustomFormat() throws {
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

        #expect(render(template, ["now": .int(now)]) == expected)
    }

    @Test func testDateWithCustomFormatWithHTML() throws {
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

        #expect(render(template, ["now": .int(now)]) == expected)
    }

    @Test func testDateWithCustomFormatAndTimeZone() throws {
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

        #expect(render(templateNewYork, ["now": .int(now)]) == expectedNewYork)

        let templateCalifornia = """
            The date is #date(now, "yyyy-MM-dd'T'HH:mm", "America/Los_Angeles")
            """

        let expectedCalifornia = """
            The date is 2020-11-09T06:30
            """

        try #expect(render(templateCalifornia, ["now": .int(now)]) == expectedCalifornia)
    }

    @Test func testDumpContext() throws {
        let data: [String: LeafData] = ["value": 12345]
        let template = """
            dumpContext should output debug description #dumpContext
            """

        let expected = """
            dumpContext should output debug description [value: "12345"]
            """

        try #expect(render(template, data) == expected)
    }

    #if !os(Android)
    @Test func testPerformance() throws {
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
            ),
        ]

        do {
            _ = try render(template, context)
        } catch {
            fatalError("render failed: \(error)")
        }
    }
    #endif
}
