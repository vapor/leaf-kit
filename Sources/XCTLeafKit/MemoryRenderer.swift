@testable import LeafKit

/// Always uses in-memory file source and clears files/cache before tests.
///
/// Disallows changing the renderer setup and source
///
/// Defaults to `EmbeddedEventLoop` as the ELG. If using MTELG, test is responsible for tearing it down.
/// Defaults to `DefaultLeafCache`, no special handling required for changes.
///
/// Adds `render(raw: String...` method for testing a String without using the source
open class MemoryRendererTestCase: LeafKitTestCase {
    final public var files: LeafMemorySource { super.source as! LeafMemorySource }
    
    final public override var source: LeafSource { get { super.source } set {} }
    final public override var renderer: LeafRenderer { get { super.renderer } set {} }
    
    final public override func setUpLeaf() throws {
        source = LeafMemorySource()
        files.dropAll()
        cache.dropAll()
    }
    
    /// Convenience for rendering a raw string immediately - requires underlying ELG be embedded
    final public func render(raw: String,
                             _ context: LeafRenderer.Context = .emptyContext(),
                             options: LeafRenderer.Options = []) throws -> String {
        let key = "_raw_x\(files.keys.count)"
        files[key] = raw
        return try super.render(key, from: "$", context, options: options)
    }
}
