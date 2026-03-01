import Foundation

enum OverviewPrioritySortMode: String, CaseIterable, Identifiable, Sendable {
    case providerOrder
    case mostConstrained
    case bestAvailable
    case nextResetSoonest

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .providerOrder: "Provider order"
        case .mostConstrained: "Most constrained first"
        case .bestAvailable: "Best available first"
        case .nextResetSoonest: "Next reset soonest"
        }
    }

    var subtitle: String {
        switch self {
        case .providerOrder:
            "Use the provider order from Settings > Providers."
        case .mostConstrained:
            "Show the provider closest to its cap first."
        case .bestAvailable:
            "Prioritize providers with the most headroom."
        case .nextResetSoonest:
            "Prioritize providers that reset soonest."
        }
    }
}
