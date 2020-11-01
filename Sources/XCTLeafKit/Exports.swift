@_exported import XCTest
@_exported import LeafKit

/// Assert that the expression errors, and that the error's `localizedDescription` contains the specified string
public func LKXCAssertErrors<T>(_ expression: @autoclosure () throws -> T,
                                contains: @autoclosure () -> String,
                                _ message: @autoclosure () -> String = "",
                                file: StaticString = #file,
                                line: UInt = #line) {
    do { _ = try expression(); XCTFail("Expression did not throw an error", file: file, line: line) }
    catch {
        let x = "Actual Error:\n\(error.localizedDescription)"
        let y = message()
        let z = contains()
        XCTAssert(!z.isEmpty, "Empty substring will catch all errors", file: file, line: line)
        XCTAssert(x.contains(z), y.isEmpty ? x : y, file: file, line: line)
    }
}
