import XCTest
@testable import LeafKit

final class LeafKitTests: XCTestCase {
    func testParser() throws {
        let template = """
        Hello #(name)!

        Hello #get(name)!

        #set(name):
            Hello #(name)
        #endset!

        #if(a):b#endif

        #if(foo):
        123
        #elseif(bar):
        456
        #else:
        789
        #endif

        #import("title")

        #import("body")

        #extend("base"):
            #export("title", "Welcome")
            #export("body"):
                Hello, #(name)!
            #endexport
        #endextend

        More stuff here!
        """
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.write(string: template)
        
        var lexer = LeafLexer(template: buffer)
        let tokens = try lexer.lex()
        print()
        print("Tokens:")
        tokens.forEach { print($0) }
        print()
        
        var parser = LeafParser(tokens: tokens)
        let ast = try parser.parse()
        print("AST:")
        ast.forEach { print($0) }
        print()
        
        var serializer = LeafSerializer(ast: ast, context: [
            "name": "Tanner",
            "a": true,
            "bar": true
        ])
        var view = try serializer.serialize()
        let string = view.readString(length: view.readableBytes)!
        print("View:")
        print(string)
        print()
    }

    static var allTests = [
        ("testParser", testParser),
    ]
}
