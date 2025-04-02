import Foundation
import NIOCore
import NIOFileSystem
import NIOPosix

/// Reference and default implementation of `LeafSource` adhering object that provides a non-blocking
/// file reader for `LeafRenderer`
///
/// Default initializer will
public struct NIOLeafFiles: LeafSource, Sendable {
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
    public struct Limit: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
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
    ///   - fileio: `NonBlockingFileIO` file object. This is no longer used but must still be passed.
    ///   - limits: Options for constraining which files may be read - see `NIOLeafFiles.Limit`
    ///   - sandboxDirectory: Full path of the lowest directory which may be escaped to
    ///   - viewDirectory: Full path of the default directory templates are relative to
    ///   - defaultExtension: The default extension inferred files will have (defaults to `leaf`)
    ///
    /// `viewDirectory` must be contained within (or overlap) `sandboxDirectory`
    public init(
        fileio _: NonBlockingFileIO,
        limits: Limit = .default,
        sandboxDirectory: String = "/",
        viewDirectory: String = "/",
        defaultExtension: String = "leaf"
    ) {
        self.limits = limits
        self.extension = defaultExtension
        let sD = URL(fileURLWithPath: sandboxDirectory, isDirectory: true).standardized.path.appending("/")
        let vD = URL(fileURLWithPath: viewDirectory, isDirectory: true).standardized.path.appending("/")
        // Ensure provided sandboxDir is directly reachable from viewDir, otherwise only use viewDir
        assert(vD.starts(with: sD), "View directory must be inside sandbox directory")
        self.sandbox = vD.starts(with: sD) ? sD : vD
        self.viewRelative = String(vD.dropFirst(sD.count))
    }

    /// Conformance to `LeafSource` to allow `LeafRenderer` to request a template.
    /// - Parameters:
    ///   - template: Relative template name (eg: `"path/to/template"`)
    ///   - escape: If the adherent represents a filesystem or something scoped that enforces
    ///             a concept of directories and sandboxing, whether to allow escaping the view directory
    ///   - eventLoop: `EventLoop` on which to perform file access
    /// - Returns: A succeeded `EventLoopFuture` holding a `ByteBuffer` with the raw
    ///            template, or an appropriate failed state ELFuture (not found, illegal access, etc)
    public func file(template: String, escape: Bool = false, on eventLoop: any EventLoop) throws -> EventLoopFuture<ByteBuffer> {
        var templateURL = URL(fileURLWithPath: self.sandbox)
            .appendingPathComponent(self.viewRelative, isDirectory: true)
            .appendingPathComponent(template, isDirectory: false)

        /// If default extension is enforced for template files, add it if it's not on the file, or if no extension present
        if self.limits.contains(.onlyLeafExtensions), templateURL.pathExtension != self.extension {
            templateURL.appendPathExtension(self.extension)
        } else if self.limits.contains(.requireExtensions), templateURL.pathExtension == "" {
            templateURL.appendPathExtension(self.extension)
        }

        let template = templateURL.standardized.path

        if !self.limits.isDisjoint(with: .dirLimited), [".", "/"].contains(template.first) {
            /// If sandboxing is enforced and the path contains a potential escaping path, look harder
            if self.limits.contains(.toVisibleFiles) {
                let protected = template.split(separator: "/")
                    .compactMap {
                        guard $0.count > 1, $0.first == ".", !$0.starts(with: "..") else { return nil }
                        return String($0)
                    }
                    .joined(separator: ",")
                if !protected.isEmpty {
                    throw LeafError(.illegalAccess("Attempted to access \(protected)"))
                }
            }
            
            if self.limits.contains(.toSandbox) {
                let limitedTo = escape ? self.sandbox : self.sandbox + self.viewRelative
                guard template.starts(with: limitedTo) else {
                    throw LeafError(.illegalAccess("Attempted to escape sandbox: \(template)"))
                }
            }
        }

        return self.read(path: template, on: eventLoop)
    }
    
    // MARK: - Internal/Private Only

    let limits: Limit
    let sandbox: String
    let viewRelative: String
    let `extension`: String
    
    /// Attempt to read a fully pathed template and return a ByteBuffer or fail
    private func read(path: String, on eventLoop: any EventLoop) -> EventLoopFuture<ByteBuffer> {
        eventLoop.makeFutureWithTask {
            do {
                return try await FileSystem.shared.withFileHandle(forReadingAt: .init(path)) { fh in
                    try await fh.readToEnd(maximumSizeAllowed: .gibibytes(2))
                }
            } catch let error as FileSystemError where error.code == .notFound {
                throw LeafError(.noTemplateExists(path))
            }
        }
    }
}
