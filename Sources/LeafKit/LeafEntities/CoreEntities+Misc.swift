import Foundation

/// A time interval relative to the specificed base date
///
/// Default value for the reference date is the Swift Date `referenceDate` (2001-01-01 00:00:00 +0000)
public struct LeafTimeInterval: LeafFunction, DoubleReturn {
    public static var callSignature: CallParameters {[
        .init(types: [.int, .double, .string], defaultValue: "now"),
        .string(labeled: "since", defaultValue: referenceBase.leafData),
    ]}
    public static let invariant: Bool = false
    
    public func evaluate(_ params: CallValues) -> LeafData {
        guard let base = ReferenceBase(rawValue: params[1].string!) else { return .trueNil }
        let offset = base.interval
        if LKDTypeSet.numerics.contains(params[0].celf) {
            return .double(Date(timeIntervalSinceReferenceDate: offset + params[0].double!)
                            .timeIntervalSinceReferenceDate) }
        guard let x = ReferenceBase(rawValue: params[0].string!) else { return .trueNil }
        return .double(base == x ? 0 : x.interval - offset)
    }
    
    @LeafRuntimeGuard public static var referenceBase: ReferenceBase = .referenceDate
            
    public enum ReferenceBase: String, RawRepresentable, LeafDataRepresentable {
        case now
        case unixEpoch
        case referenceDate
        case distantPast
        case distantFuture
        
        public var leafData: LeafData { .string(rawValue) }
        
        internal var interval: Double {
            switch self {
                case .now: return Date().timeIntervalSinceReferenceDate
                case .unixEpoch: return -1 * Date.timeIntervalBetween1970AndReferenceDate
                case .referenceDate: return 0
                case .distantFuture: return Date.distantFuture.timeIntervalSinceReferenceDate
                case .distantPast: return Date.distantPast.timeIntervalSinceReferenceDate
            }
        }
    }
}

public struct LeafDateFormatter: LeafMethod, StringReturn {
    public static var mutating: Bool { false }
    public static var invariant: Bool { true }
    
    public static var callSignature: CallParameters {[
        .double,
        .string(labeled: "format", defaultValue: defaultFormat.leafData),
        .double(labeled: "offset", defaultValue: defaultTZOffset.leafData)
    ]}
    
    public func evaluate(_ params: CallValues) -> LeafData {
        .trueNil
    }
    public func mutatingEvaluate(_ params: CallValues) -> (mutate: LeafData?, result: LeafData) {
        __MajorBug("Non-mutating") }
    
    @LeafRuntimeGuard public static var defaultFormat: String = "YYYY-MM-dd"
    @LeafRuntimeGuard public static var defaultTZOffset: Double = 0.0
    @LeafRuntimeGuard public static var formatters: [String: DateFormatter] = [:]
}
