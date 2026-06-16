import Foundation

/// Ranks fleet peers by operational urgency for director attention.
enum SignalRanker {
    static let attentionThreshold = 50

    /// Score a peer — higher values demand more attention.
    ///
    /// - degraded bootState: 100
    /// - offline: 80
    /// - stale status: 60
    /// - DM unread (when passed): 50
    /// - watchlisted idle: 20
    /// - active/thinking: 0
    static func score(
        peer: Peer,
        watchlist: Set<String>,
        dmUnreadAgents: Set<String> = []
    ) -> Int {
        var scores = [0]

        if peer.bootState == "degraded" {
            scores.append(100)
        }
        if peer.status == .offline {
            scores.append(80)
        }
        if peer.status == .stale {
            scores.append(60)
        }
        if dmUnreadAgents.contains(peer.agentName) {
            scores.append(50)
        }
        if watchlist.contains(peer.agentName), peer.status == .idle {
            scores.append(20)
        }

        return scores.max() ?? 0
    }

    /// Peers with score >= 50, sorted by score descending.
    static func needsAttention(
        peers: [Peer],
        watchlist: Set<String>,
        dmUnreadAgents: Set<String> = []
    ) -> [Peer] {
        peers
            .filter {
                score(peer: $0, watchlist: watchlist, dmUnreadAgents: dmUnreadAgents) >= attentionThreshold
            }
            .sorted { lhs, rhs in
                let left = score(peer: lhs, watchlist: watchlist, dmUnreadAgents: dmUnreadAgents)
                let right = score(peer: rhs, watchlist: watchlist, dmUnreadAgents: dmUnreadAgents)
                if left != right { return left > right }
                return lhs.agentName < rhs.agentName
            }
    }
}