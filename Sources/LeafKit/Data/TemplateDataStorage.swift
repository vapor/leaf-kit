internal enum TemplateDataStorage {
    /// A `Bool`.
    ///
    ///     true
    ///
    case bool(Bool)

    /// A `String`.
    ///
    ///     "hello"
    ///
    case string(String)

    /// An `Int`.
    ///
    ///     42
    ///
    case int(Int)

    /// A `Double`.
    ///
    ///     3.14
    ///
    case double(Double)

    /// `Data` blob.
    ///
    ///     Data([0x72, 0x73])
    ///
    case data(Data)

    /// A nestable `[String: TemplateData]` dictionary.
    case dictionary([String: TemplateData])

    /// A nestable `[TemplateData]` array.
    case array([TemplateData])

    /// A lazily-resolvable `TemplateData`.
    case lazy(() -> (TemplateData))

    /// Null.
    case null
}
