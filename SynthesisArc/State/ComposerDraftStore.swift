import Foundation

/// Persists composer text across rotation and column switches (spec: never clear on rotate).
@MainActor
final class ComposerDraftStore: ObservableObject {
    @Published private var drafts: [String: String] = [:]

    func text(for key: String) -> String {
        drafts[key] ?? ""
    }

    func setText(_ value: String, for key: String) {
        var copy = drafts
        if value.isEmpty {
            copy.removeValue(forKey: key)
        } else {
            copy[key] = value
        }
        drafts = copy
    }

    static func channelKey(_ name: String) -> String { "channel:\(name)" }
    static func inboxKey(_ sender: String) -> String { "inbox:\(sender)" }
    static func fleetDMKey(_ agent: String) -> String { "fleet-dm:\(agent)" }
    static func channelDMKey(channel: String, agent: String) -> String { "channel-dm:\(channel):\(agent)" }
}