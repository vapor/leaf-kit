import XCTest

@testable import LeafKitTests

// MARK: LeafKitTests

extension LeafKitTests {
	static let __allLeafKitTestsTests = [
		("testParser", testParser),
		("testLoader", testLoader),
		("testParserasdf", testParserasdf),
		("testNestedEcho", testNestedEcho),
	]
}

extension LeafKitTests.LeafTests {
	static let __allLeafTestsTests = [
		("testComplexIf", testComplexIf),
		("testRaw", testRaw),
		("testPrint", testPrint),
		("testConstant", testConstant),
		("testNested", testNested),
		("testExpression", testExpression),
		("testBody", testBody),
		("testForSugar", testForSugar),
		("testIfSugar", testIfSugar),
		("testNot", testNot),
		("testNestedBodies", testNestedBodies),
		("testDotSyntax", testDotSyntax),
		("testEqual", testEqual),
	]
}

extension LeafKitTests.LexerTests {
	static let __allLexerTestsTests = [
		("testParamNesting", testParamNesting),
		("testConstant", testConstant),
		("testEscaping", testEscaping),
		("testTagIndicator", testTagIndicator),
		("testParameters", testParameters),
		("testTags", testTags),
		("testNestedEcho", testNestedEcho),
	]
}

extension LeafKitTests.ParserTests {
	static let __allParserTestsTests = [
		("testNesting", testNesting),
		("testParsingNesting", testParsingNesting),
		("testComplex", testComplex),
		("testCompiler", testCompiler),
		("testCompiler2", testCompiler2),
		("testShouldThrowCantResolve", testShouldThrowCantResolve),
		("testInsertResolution", testInsertResolution),
		("testDocumentResolveExtend", testDocumentResolveExtend),
		("testCompileExtend", testCompileExtend),
		("testPPP", testPPP),
	]
}

extension LeafKitTests.PrintTests {
	static let __allPrintTestsTests = [
		("testRaw", testRaw),
		("testVariable", testVariable),
		("testLoop", testLoop),
		("testConditional", testConditional),
		("testImport", testImport),
		("testExtendAndExport", testExtendAndExport),
		("testCustomTag", testCustomTag),
	]
}

extension LeafKitTests.SerializerTests {
	static let __allSerializerTestsTests = [
		("testComplex", testComplex),
	]
}

extension LeafKitTests.SomeTests {
	static let __allSomeTestsTests = [
		("testCodable", testCodable),
	]
}

// MARK: Test Runner

#if !os(macOS)
public func __buildTestEntries() -> [XCTestCaseEntry] {
	return [
		// LeafKitTests
		testCase(LeafKitTests.__allLeafKitTestsTests),
		testCase(LeafTests.__allLeafTestsTests),
		testCase(LexerTests.__allLexerTestsTests),
		testCase(ParserTests.__allParserTestsTests),
		testCase(PrintTests.__allPrintTestsTests),
		testCase(SerializerTests.__allSerializerTestsTests),
		testCase(SomeTests.__allSomeTestsTests),
	]
}

let tests = __buildTestEntries()
XCTMain(tests)
#endif

