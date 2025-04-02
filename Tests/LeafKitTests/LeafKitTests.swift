import NIOCore
import NIOPosix
import Testing

@testable import LeafKit

@Suite
struct LeafKitTests {
    func testNestedEcho() throws {
        let input = """
            Todo: #(todo.title)
            """
        var lexer = LeafLexer(name: "nested-echo", template: input)
        let tokens = try lexer.lex()
        var parser = LeafParser(name: "nested-echo", tokens: tokens)
        let ast = try parser.parse()
        var serializer = LeafSerializer(ast: ast, ignoreUnfoundImports: false)
        let view = try serializer.serialize(context: ["todo": ["title": "Leaf!"]])
        #expect(view.string == "Todo: Leaf!")
    }

    func testRendererContext() async throws {
        var test = TestFiles()
        test.files["/foo.leaf"] = "Hello #custom(name)"

        struct CustomTag: LeafTag {
            func render(_ ctx: LeafContext) throws -> LeafData {
                let prefix = ctx.userInfo["prefix"] as? String ?? ""
                let param = ctx.parameters.first?.string ?? ""
                return .string(prefix + param)
            }
        }

        let renderer = TestRenderer(
            tags: ["custom": CustomTag()],
            sources: .init(singleSource: test),
            userInfo: ["prefix": "bar"]
        )

        #expect(try await renderer.render(path: "foo", context: ["name": "vapor"]).string == "Hello barvapor")
    }

    func testImportResolve() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = """
            #extend("b"):
            #export("variable"):Hello#endexport
            #endextend
            """
        test.files["/b.leaf"] = """
            #import("variable")
            """

        let renderer = TestRenderer(sources: .init(singleSource: test))

        #expect(try await renderer.render(path: "a").string == "Hello")
    }

    #if !os(Android)
    func _testCacheSpeedLinear(templates: Int, iterations: Int) async throws {
        var test = TestFiles()

        for name in 1...templates { test.files["/\(name).leaf"] = "Template /\(name).leaf" }
        let renderer = TestRenderer(
            sources: .init(singleSource: test)
        )

        for iteration in 1...iterations {
            let template = String((iteration % templates) + 1)
            _ = try await renderer.render(path: template)
        }

        await #expect(renderer.r.cache.count == templates)
    }

    func _testCacheSpeedRandom(layer1: Int, layer2: Int, layer3: Int, iterations: Int) async throws {
        var test = TestFiles()

        for name in 1...layer3 { test.files["/\(name)-3.leaf"] = "Template \(name)" }
        for name in 1...layer2 { test.files["/\(name)-2.leaf"] = "Template \(name) -> #extend(\"\((name % layer3)+1)-3\")" }
        for name in 1...layer1 {
            test.files["/\(name).leaf"] =
                "Template \(name) -> #extend(\"\(Int.random(in: 1...layer2))-2\") & #extend(\"\(Int.random(in: 1...layer2))-2\")"
        }

        let allKeys: [String] = test.files.keys.map { String($0.dropFirst().dropLast(5)) }.shuffled()
        var hitList = allKeys
        let totalTemplates = allKeys.count
        let ratio = iterations / allKeys.count

        let renderer = TestRenderer(sources: .init(singleSource: test))

        for x in (0..<iterations).reversed() {
            let template: String
            if x / ratio < hitList.count {
                template = hitList.removeFirst()
            } else {
                template = allKeys[Int.random(in: 0..<totalTemplates)]
            }
            _ = try await renderer.render(path: template)
        }

        await #expect(renderer.r.cache.count == layer1 + layer2 + layer3)
    }
    #endif

    func testImportParameter() async throws {
        var test = TestFiles()
        test.files["/base.leaf"] = """
            #extend("parameter"):
                #export("admin", admin)
            #endextend
            """
        test.files["/delegate.leaf"] = """
            #extend("parameter"):
                #export("delegated", false || bypass)
            #endextend
            """
        test.files["/parameter.leaf"] = """
            #if(import("admin")):
                Hi Admin
            #elseif(import("delegated")):
                Also an admin
            #else:
                No Access
            #endif
            """

        let renderer = TestRenderer(sources: .init(singleSource: test))

        #expect(try await renderer.render(path: "base", context: ["admin": false]).string == "\n    No Access\n")
        #expect(try await renderer.render(path: "base", context: ["admin": true]).string == "\n    Hi Admin\n")
        #expect(try await renderer.render(path: "delegate", context: ["bypass": true]).string == "\n    Also an admin\n")
    }

    func testDeepResolve() async throws {
        var test = TestFiles()
        test.files["/a.leaf"] = """
            #for(a in b):#if(false):Hi#elseif(true && false):Hi#else:#extend("b"):#export("derp"):DEEP RESOLUTION #(a)#endexport#endextend#endif#endfor
            """
        test.files["/b.leaf"] = """
            #import("derp")

            """

        let expected = """
            DEEP RESOLUTION 1
            DEEP RESOLUTION 2
            DEEP RESOLUTION 3

            """

        let renderer = TestRenderer(sources: .init(singleSource: test))

        #expect(try await renderer.render(path: "a", context: ["b": ["1", "2", "3"]]).string == expected)
    }

    // The #filePath trick this test relies on doesn't work in the Android CI because the build
    // machine is not the same box as the test machine; we'd need to turn the templates into working
    // resources for that. Disable for now.
    #if !os(Android)
    func testFileSandbox() async throws {
        let renderer = TestRenderer(
            configuration: .init(rootDirectory: templateFolder),
            sources: .init(
                singleSource: NIOLeafFiles(
                    fileio: .init(threadPool: NIOSingletons.posixBlockingThreadPool),
                    limits: .default,
                    sandboxDirectory: templateFolder,
                    viewDirectory: templateFolder + "/SubTemplates"
                ))
        )

        await #expect(throws: Never.self) { try await renderer.render(path: "test") }
        await #expect(throws: Never.self) { try await renderer.render(path: "../test") }

        let escapingSandboxError = await #expect(throws: LeafError.self) { try await renderer.render(path: "../../test") }
        #expect(escapingSandboxError.localizedDescription.contains("Attempted to escape sandbox") ?? false)

        let testAccessError = await #expect(throws: LeafError.self) { try await renderer.render(path: ".test") }
        #expect(testAccessError.localizedDescription.contains("Attempted to access .test") ?? false)

        #expect(renderer.isDone)
    }
    #endif

    func testMultipleSources() async throws {
        var sourceOne = TestFiles()
        var sourceTwo = TestFiles()
        sourceOne.files["/a.leaf"] = "This file is in sourceOne"
        sourceTwo.files["/b.leaf"] = "This file is in sourceTwo"

        let multipleSources = LeafSources()
        try await multipleSources.register(using: sourceOne)
        try await multipleSources.register(source: "sourceTwo", using: sourceTwo)

        let unsearchableSources = LeafSources()
        try await unsearchableSources.register(source: "unreachable", using: sourceOne, searchable: false)

        let goodRenderer = TestRenderer(sources: multipleSources)
        let emptyRenderer = TestRenderer(sources: unsearchableSources)

        await #expect(goodRenderer.r.sources.all.contains("sourceTwo"))
        await #expect(emptyRenderer.r.sources.searchOrder.isEmpty)

        #expect(try await goodRenderer.render(path: "a").string.contains("sourceOne"))
        #expect(try await goodRenderer.render(path: "b").string.contains("sourceTwo"))

        let noTemplateFoundError = await #expect(throws: LeafError.self) { try await goodRenderer.render(path: "c") }
        #require(noTemplateFoundError.localizedDescription.contains("No template found"))
        
        let noSourcesError = await #expect(throws: LeafError.self) { try await emptyRenderer.render(path: "c") }
        #expect(noSourcesError.localizedDescription.contains("No searchable sources exist"))

    }

    func testBodyRequiring() async throws {
        var test = TestFiles()
        test.files["/body.leaf"] = "#bodytag:test#endbodytag"
        test.files["/bodyError.leaf"] = "#bodytag:#endbodytag"
        test.files["/nobody.leaf"] = "#nobodytag"
        test.files["/nobodyError.leaf"] = "#nobodytag:test#endnobodytag"

        struct BodyRequiringTag: UnsafeUnescapedLeafTag {
            func render(_ ctx: LeafContext) throws -> LeafData {
                _ = try ctx.requireBody()
                return .string("Hello there")
            }
        }

        struct NoBodyRequiringTag: UnsafeUnescapedLeafTag {
            func render(_ ctx: LeafContext) throws -> LeafData {
                try ctx.requireNoBody()
                return .string("General Kenobi")
            }
        }

        let renderer = TestRenderer(
            tags: [
                "bodytag": BodyRequiringTag(),
                "nobodytag": NoBodyRequiringTag(),
            ],
            sources: .init(singleSource: test)
        )

        #expect(try await renderer.render(path: "body", context: ["test": "ciao"]).string == "Hello there")
        await #expect(throws: (any Error).self) { try await renderer.render(path: "bodyError", context: [:]) }

        #expect(try await renderer.render(path: "nobody", context: [:]).string == "General Kenobi")
        await #expect(throws: (any Error).self) { try await renderer.render(path: "nobodyError", context: [:]) }
    }
}
