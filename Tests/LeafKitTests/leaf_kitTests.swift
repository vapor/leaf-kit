import XCTest
@testable import LeafKit

final class LeafKitTests: XCTestCase {
    func testParser() throws {
        let template = """
        Hello #get(name)!

        #set(name):
            Hello #(name)
        #endset!

        #if(foo):
        123
        #else:
        321
        #endif
        """
//
//        More stuff here!
//        """
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
    }

    static var allTests = [
        ("testParser", testParser),
    ]
}
