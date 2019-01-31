import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(leaf_kitTests.allTests),
    ]
}
#endif
