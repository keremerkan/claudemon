import Foundation

/// The floating window's form. Persisted by `UsageStore` as a raw string,
/// cycled by a double-click on the panel and chosen in the panel's settings.
public enum FloatingForm: String, CaseIterable, Identifiable, Sendable {
    case rings
    case slim
    case mini

    public var id: String { rawValue }

    public init(legacyCompact: Bool) {
        self = legacyCompact ? .mini : .rings
    }

    public var next: FloatingForm {
        switch self {
        case .rings: return .slim
        case .slim: return .mini
        case .mini: return .rings
        }
    }

    public var label: String {
        switch self {
        case .rings: return "Rings"
        case .slim: return "Slim"
        case .mini: return "Mini"
        }
    }
}
