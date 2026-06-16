import Foundation

/// Optional ops-graph fleet posture snapshot (JSON stub endpoint).
struct FleetPosture: Codable, Equatable {
    let repos: Int
    let violations: Int
    let deadCode: Int

    /// Primary director-console line.
    var summaryLine: String {
        "Fleet code posture: \(violations) violations across \(repos) repos"
    }

    var deadCodeLine: String? {
        guard deadCode > 0 else { return nil }
        return "\(deadCode) dead-code symbol\(deadCode == 1 ? "" : "s") flagged"
    }

    var hasIssues: Bool {
        violations > 0 || deadCode > 0
    }
}

@MainActor
final class OpsGraphService: ObservableObject {
    @Published private(set) var posture: FleetPosture?
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch posture JSON from configured URL; returns nil when URL unset or fetch/decode fails.
    func fetchFleetPosture() async -> FleetPosture? {
        let urlString = AppConfig.shared.opsGraphStatsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            posture = nil
            error = nil
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                error = "Ops graph HTTP \(code)"
                posture = nil
                return nil
            }
            let decoded = try JSONDecoder().decode(FleetPosture.self, from: data)
            posture = decoded
            error = nil
            return decoded
        } catch {
            self.error = error.localizedDescription
            posture = nil
            return nil
        }
    }
}