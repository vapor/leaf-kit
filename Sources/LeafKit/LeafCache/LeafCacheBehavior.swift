/// Behaviors for how render calls will use the configured `LeafCache` for compiled templates
public struct LeafCacheBehavior: OptionSet, Hashable {
    public private(set) var rawValue: UInt8
    
    public init(rawValue: RawValue) { self.rawValue = rawValue }
    
    /// - Prefer reading cached (compiled) templates over checking source
    /// - Always store compiled templates and/or further-resovled templates
    /// - Cache `raw` inlines up to the configured limit size
    public static let `default`: Self = [
        .read, .store, .embedRawInlines, .limitRawInlines, .autoUpdate
    ]
    
    /// Avoid using caching entirely
    public static let bypass: Self = []
    
    /// Never read cached template, but cache compiled template.
    /// Disregards `raw` inline configuration as if it's followed by a subsequent update, there's no point
    /// and if it's followed by a default behavior, embedding raws will happen then.
    public static let update: Self = [.store]
    
    /// Whether to prefer reading an available cached version over checking `LeafSources`
    static let read: Self = .init(rawValue: 1 << 0)
    /// Whether to store a valid compiled template, when parsing has occurred
    static let store: Self = .init(rawValue: 1 << 1)
    /// Embed `#inline(...)` in cached ASTs
    // static let embedLeafInlines: Self = .init(rawValue: 1 << 2)
    /// Embed `#inline(..., as: raw)` in cached ASTs
    static let embedRawInlines: Self = .init(rawValue: 1 << 3)
    /// Limit the filesize of raws to associated limit, if `cacheRawInlines` is set. Controls nothing by itself.
    static let limitRawInlines: Self = .init(rawValue: 1 << 4)
    
    static let autoUpdate: Self = .init(rawValue: 1 << 5)
}
