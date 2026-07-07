import Foundation

/// Routes notification taps and custom URL opens into command center selection.
enum DeepLinkRoute: Equatable {
    case fleet(agent: String)
    case inbox(sender: String)
    case channel(name: String)

    init?(url: URL) {
        guard url.scheme == "synthesisarc" else { return nil }
        let path = url.host ?? ""
        let components = url.pathComponents.filter { $0 != "/" }
        switch path {
        case "fleet":
            guard let agent = components.first else { return nil }
            self = .fleet(agent: agent)
        case "inbox":
            guard let sender = components.first else { return nil }
            self = .inbox(sender: sender)
        case "channel":
            guard let name = components.first else { return nil }
            self = .channel(name: name)
        default:
            return nil
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let route = Self.string(userInfo, keys: "route", "type", "destination") else { return nil }
        switch route {
        case "fleet":
            guard let agent = Self.string(userInfo, keys: "agent", "peer", "agentName") else { return nil }
            self = .fleet(agent: agent)
        case "inbox", "dm":
            guard let sender = Self.string(userInfo, keys: "sender", "peer", "from", "agent") else { return nil }
            self = .inbox(sender: sender)
        case "channel":
            guard let name = Self.string(userInfo, keys: "channel", "channel_name", "name") else { return nil }
            self = .channel(name: name)
        default:
            return nil
        }
    }

    /// Audit-friendly label — no message bodies.
    var auditLabel: String {
        switch self {
        case .fleet(let agent): return "fleet/\(agent)"
        case .inbox(let sender): return "inbox/\(sender)"
        case .channel(let name): return "channel/\(name)"
        }
    }

    private static func string(_ userInfo: [AnyHashable: Any], keys: String...) -> String? {
        for key in keys {
            if let value = userInfo[AnyHashable(key)] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = userInfo[AnyHashable(key)] as? NSString {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed as String }
            }
        }
        return nil
    }

    var userInfo: [String: String] {
        switch self {
        case .fleet(let agent):
            return ["route": "fleet", "agent": agent]
        case .inbox(let sender):
            return ["route": "inbox", "sender": sender]
        case .channel(let name):
            return ["route": "channel", "channel": name]
        }
    }
}