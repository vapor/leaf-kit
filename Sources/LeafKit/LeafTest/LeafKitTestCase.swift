import XCTest
import Dispatch

open class LeafKitTestCase: XCTestCase {
    /// Override for per-test setup
    open func setUpLeaf() throws {}
        
    final public override class func setUp() { Self.queue.sync { _resetLeaf() } }
    
    final public override func setUpWithError() throws {
        try Self.queue.sync {
            addTeardownBlock {
                Self._resetLeaf()
                if let files = self.source as? LeafMemorySource { files.dropAll() }
                self.cache.dropAll()
            }
            try setUpLeaf()
        }
    }
        
    open var eLGroup: EventLoopGroup = EmbeddedEventLoop()
    
    open var source: LeafSource = LeafMemorySource()
    open var cache: LeafCache = DefaultLeafCache()
    
    open var renderer: LeafRenderer { LeafRenderer(cache: cache,
                                                   sources: .singleSource(source),
                                                   eventLoop: eLGroup.next()) }
    
    @discardableResult
    final public func render(_ template: String,
                             from source: String = "$",
                             _ context: LeafRenderer.Context = .emptyContext(),
                             options: LeafOptions = []) throws -> String {
        precondition(renderer.eventLoop is EmbeddedEventLoop,
                     "Non-future render call must be on EmbeddedEventLoop")
        return try renderBuffer(template, from: source, context, options: options)
                    .map { String(decoding: $0.readableBytesView, as: UTF8.self) }.wait()
    }
    
    @discardableResult
    public func renderBuffer(_ template: String,
                             from source: String = "$",
                             _ context: LeafRenderer.Context = .emptyContext(),
                             options: LeafRenderer.Options = []) -> EventLoopFuture<ByteBuffer> {
        renderer.render(template: template, from: source, context: context, options: options)
    }
    
    final public func AssertErrors<T>(_ expression: @autoclosure () throws -> T,
                                      contains: @autoclosure () -> String,
                                      _ message: @autoclosure () -> String = "",
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        do { _ = try expression(); XCTFail("Expression did not throw an error", file: file, line: line) }
        catch {
            let x = "Actual Error: `\(error.localizedDescription)`"
            let y = message()
            let z = contains()
            XCTAssert(!z.isEmpty, "Empty substring will catch all errors", file: file, line: line)
            XCTAssert(x.contains(z), y.isEmpty ? x : y, file: file, line: line)
        }
    }
    
    private static var queue = DispatchQueue(label: "LeafKitTests")
}

internal extension LeafKitTestCase {
    func startLeafKit() {
        _primeLeaf()
        if !LKConf.started { LKConf.started = true }
    }
    
    @discardableResult
    func lex(raw: String, name: String = "rawTemplate") throws -> [LKToken] {
        startLeafKit()
        var lexer = LKLexer(LKRawTemplate(name, raw))
        return try lexer.lex()
    }
    
    @discardableResult
    func parse(raw: String, name: String = "rawTemplate",
               context: LKRContext = [:],
               options: LeafRenderer.Options = []) throws -> LeafAST {
        let tokens = try lex(raw: raw, name: name)
        var context = context
        if context.options == nil { context.options = options }
        else { options._storage.forEach { context.options!.update($0) } }
        var parser = LKParser(.searchKey(name), tokens, context)
        return try parser.parse()
    }
}

private extension LeafKitTestCase {
    func _primeLeaf() { if !LKConf.isRunning { LKConf.entities = .leaf4Core } }
    
    static func _resetLeaf() {
        #if DEBUG
        started = false
        #else
        fatalError("DO NOT USE IN NON-DEBUG BUILDS")
        #endif
        
        LeafConfiguration.tagIndicator = .octothorpe
        LeafConfiguration.entities = .leaf4Core
        
        LeafRenderer.Option.timeout = 0.050
        LeafRenderer.Option.parseWarningThrows = true
        LeafRenderer.Option.missingVariableThrows = true
        LeafRenderer.Option.grantUnsafeEntityAccess = false
        LeafRenderer.Option.encoding = .utf8
        LeafRenderer.Option.caching = .default
        LeafRenderer.Option.embeddedASTRawLimit = 4096
        LeafRenderer.Option.pollingFrequency = 10.0
        
        LeafBuffer.boolFormatter = { $0.description }
        LeafBuffer.intFormatter = { $0.description }
        LeafBuffer.doubleFormatter = { $0.description }
        LeafBuffer.nilFormatter = { _ in "" }
        LeafBuffer.stringFormatter = { $0 }
        LeafBuffer.dataFormatter = { String(data: $0, encoding: $1) }
        
        DoubleFormatterMap.defaultPlaces = 2
        IntFormatterMap.defaultPlaces = 2
        
        LeafTimestamp.referenceBase = .referenceDate
        LeafDateFormatters.defaultFractionalSeconds = false
        LeafDateFormatters.defaultTZIdentifier = "UTC"
        LeafDateFormatters.defaultLocale = "en_US_POSIX"
        
        LeafSources.rootDirectory = "/"
        LeafSources.defaultExtension = "leaf"
    }
}
