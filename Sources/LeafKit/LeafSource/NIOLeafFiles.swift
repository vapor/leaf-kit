import Foundation

/// Reference and default implementation of `LeafSource` adhering object that provides a non-blocking
/// file reader for `LeafRenderer`
///
/// Default initializer will
public struct NIOLeafFiles: LeafSource {
    // MARK: - Public
    
    /// Various options for configuring an instance of `NIOLeafFiles`
    ///
    /// - `.requireExtensions` - When set, any template *must* have a file extension
    /// - `.onlyLeafExtensions` - When set, any template *must* use the configured extension
    /// - `.toSandbox` - When set, attempts to read files outside of the sandbox directory will error
    /// - `.toVisibleFiles` - When set, attempts to read files starting with `.` will error (or files
    ///                     inside a directory starting with `.`)
    ///
    /// A new `NIOLeafFiles` defaults to [.toSandbox, .toVisibleFiles, .requireExtensions]
    public struct Limit: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        
        /// Require any referenced file have an extension
        public static let requireExtensions = Limit(rawValue: 1 << 0)
        /// Require any referenced file end in `.leaf`
        public static let onlyLeafExtensions = Limit(rawValue: 1 << 1)
        /// Limit access to inside configured sandbox directory
        public static let toSandbox = Limit(rawValue: 1 << 2)
        /// Limit access to visible files/directories
        public static let toVisibleFiles = Limit(rawValue: 1 << 3)
        
        public static let `default`: Limit = [.toSandbox, .toVisibleFiles, .requireExtensions]
        public static let dirLimited: Limit = [.toSandbox, .toVisibleFiles]
    }
    
    /// Initialize `NIOLeafFiles` with a NIO file IO object, limit options, and sandbox/view dirs
    /// - Parameters:
    ///   - fileio: `NonBlockingFileIO` file object
    ///   - limits: Options for constraining which files may be read - see `NIOLeafFiles.Limit`
    ///   - sandboxDirectory: Full path of the lowest directory which may be escaped to
    ///   - viewDirectory: Full path of the default directory templates are relative to
    ///   - defaultExtension: The default extension inferred files will have (defaults to `leaf`)
    ///
    /// `viewDirectory` must be contained within (or overlap) `sandboxDirectory`
    public init(fileio: NonBlockingFileIO,
                limits: Limit = .default,
                sandboxDirectory: String = "/",
                viewDirectory: String = "/",
                defaultExtension: String = "leaf") {
        self.fileio = fileio
        self.lim = limits
        self.fileExt = defaultExtension
        let sD = URL(fileURLWithPath: sandboxDirectory, isDirectory: true).standardized.path.appending("/")
        let vD = URL(fileURLWithPath: viewDirectory, isDirectory: true).standardized.path.appending("/")
        // Ensure provided sandboxDir is directly reachable from viewDir, otherwise only use viewDir
        assert(vD.hasPrefix(sD), "View directory must be inside sandbox directory")
        self.sandBox = vD.hasPrefix(sD) ? sD : vD
        self.viewDir = String(vD[sD.indices.endIndex ..< vD.indices.endIndex])
    }

    /// Conformance to `LeafSource` to allow `LeafRenderer` to request a template.
    /// - Parameters:
    ///   - template: Relative template name (eg: `"path/to/template"`)
    ///   - escape: If the adherent represents a filesystem or something scoped that enforces
    ///             a concept of directories and sandboxing, whether to allow escaping the view directory
    ///   - eventLoop: `EventLoop` on which to perform file access
    /// - Returns: A succeeded `EventLoopFuture` holding a `ByteBuffer` with the raw
    ///            template, or an appropriate failed state ELFuture (not found, illegal access, etc)
    public func file(template: String,
                     escape: Bool = false,
                     on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        /// Remove all `.` & `..` indirections
        var t = sandBox + viewDir + template
        t = URL(fileURLWithPath: t, isDirectory: false).standardized.path
        
        /// If default extension is enforced for template files, add it if it's not on the file, or if no extension present
        if lim.contains(.onlyLeafExtensions), !t.hasSuffix(".\(fileExt)")
            { t += ".\(fileExt)" }
        else if lim.contains(.requireExtensions), !t.split(separator: "/").last!.contains(".")
            { t += ".\(fileExt)" }
        
        if !lim.isDisjoint(with: .dirLimited) {
            /// If sandboxing is enforced and the path contains a potential escaping path, look harder
            if lim.contains(.toVisibleFiles), t.contains("/."),
               let hit = t.split(separator: "/").first(where: { $0.first == "."}) {
                return fail(.illegalAccess("Attempted to access \(hit)"), on: eventLoop)
            }
            
            if lim.contains(.toSandbox), !template.hasPrefix(sandBox + (escape ? viewDir : "")) {
                return fail(.illegalAccess("Attempted to escape sandbox: \(t)"), on: eventLoop)
            }
        }

        return read(path: template, on: eventLoop)
    }
    
    // MARK: - Private Only
    private let fileio: NonBlockingFileIO
    private let lim: Limit
    private let sandBox: String
    private let viewDir: String
    private let fileExt: String
    
    /// Attempt to read a fully pathed template and return a ByteBuffer or fail
    private func read(path: String, on eL: EventLoop) -> ELF<ByteBuffer> {
        fileio.openFile(path: path, eventLoop: eL)
              .flatMapError { _ in fail(.noTemplateExists(path), on: eL) }
              .flatMap { (h, r) in
                          self.fileio.read(fileRegion: r,
                                           allocator: ByteBufferAllocator(),
                                           eventLoop: eL)
                              .flatMapThrowing { try h.close()
                                                 return $0 }
                       }
    }
}
