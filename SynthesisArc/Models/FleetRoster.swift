import Foundation

// MARK: - Fleet Roster

/// Operational deployment roster — department mapping for fleet organization.
struct FleetRoster: Codable, Equatable {
    let description: String?
    let lastUpdated: String?
    let departments: [String: FleetDepartment]

    enum CodingKeys: String, CodingKey {
        case description
        case lastUpdated = "last_updated"
        case departments
    }

    struct FleetDepartment: Codable, Equatable {
        let label: String
        let description: String?
        let members: [String]
    }

    static let empty = FleetRoster(description: nil, lastUpdated: nil, departments: [:])

    /// Department key for agents not listed in the roster.
    static let otherDepartmentKey = "other"

    /// Ordered department keys — roster order with "other" last.
    var orderedDepartmentKeys: [String] {
        var keys = departments.keys.sorted()
        keys.append(Self.otherDepartmentKey)
        return keys
    }

    func label(for departmentKey: String) -> String {
        if departmentKey == Self.otherDepartmentKey {
            return "Other"
        }
        return departments[departmentKey]?.label ?? departmentKey.uppercased()
    }

    /// Map agent_name → department key.
    func departmentKey(for agentName: String) -> String {
        for (key, dept) in departments where dept.members.contains(agentName) {
            return key
        }
        return Self.otherDepartmentKey
    }

    /// All agent names listed in the roster (all departments).
    var allMemberNames: [String] {
        var names = Set<String>()
        for dept in departments.values {
            for member in dept.members {
                names.insert(member)
            }
        }
        return names.sorted()
    }
}

// MARK: - Loader

enum FleetRosterLoader {
    private static let bundledFileName = "fleet-roster"

    /// Load roster from a configurable file path (macOS dev) or the bundled copy.
    static func load(overridePath: String = "") -> FleetRoster {
        if let override = loadFromFile(path: overridePath) {
            return override
        }
        if let bundled = loadFromBundle() {
            return bundled
        }
        return .empty
    }

    private static func loadFromFile(path: String) -> FleetRoster? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FleetRoster.self, from: data)
        } catch {
            print("[FleetRoster] Failed to load override at \(expanded): \(error)")
            return nil
        }
    }

    private static func loadFromBundle() -> FleetRoster? {
        guard let url = Bundle.main.url(forResource: bundledFileName, withExtension: "json") else {
            print("[FleetRoster] fleet-roster.json not found in bundle")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FleetRoster.self, from: data)
        } catch {
            print("[FleetRoster] Failed to decode bundled roster: \(error)")
            return nil
        }
    }
}

// MARK: - Watchlist

/// Pinned agents persisted via @AppStorage (comma-separated agent names).
enum FleetWatchlist {
    static let storageKey = "fleet.watchlist"

    static func decode(_ raw: String) -> Set<String> {
        guard !raw.isEmpty else { return [] }
        return Set(
            raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    static func encode(_ agents: Set<String>) -> String {
        agents.sorted().joined(separator: ",")
    }

    static func toggle(_ agentName: String, in raw: inout String) {
        var set = decode(raw)
        if set.contains(agentName) {
            set.remove(agentName)
        } else {
            set.insert(agentName)
        }
        raw = encode(set)
    }
}

// MARK: - Fleet Section

struct FleetSection: Identifiable {
    let id: String
    let title: String
    let peers: [Peer]

    var exceptionCount: Int {
        peers.filter(\.isFleetException).count
    }
}

// MARK: - Peer Fleet Helpers

extension Peer {
    /// Non-active: degraded boot, stale, offline, or idle.
    var isFleetException: Bool {
        if bootState == "degraded" { return true }
        switch status {
        case .active, .thinking:
            return false
        case .idle, .stale, .offline:
            return true
        }
    }

    /// Lower values sort first — exceptions surface at the top of each section.
    var fleetSortOrder: Int {
        if bootState == "degraded" { return 0 }
        switch status {
        case .offline: return 1
        case .stale: return 2
        case .idle: return 3
        case .thinking: return 4
        case .active: return 5
        }
    }

    func matchesFleetSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()
        return agentName.lowercased().contains(needle)
            || displayName.lowercased().contains(needle)
    }

    var displayName: String {
        agentName
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

extension Array where Element == Peer {
    func fleetSorted() -> [Peer] {
        sorted { lhs, rhs in
            if lhs.fleetSortOrder != rhs.fleetSortOrder {
                return lhs.fleetSortOrder < rhs.fleetSortOrder
            }
            return lhs.agentName < rhs.agentName
        }
    }

    func filteredForFleetSearch(_ query: String) -> [Peer] {
        filter { $0.matchesFleetSearch(query) }
    }
}