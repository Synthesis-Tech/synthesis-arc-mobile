import Foundation

/// Persists bilateral DM threads across relaunch (graphd has no sent-DM history API).
enum DMThreadPersistence {
    private static let fileName = "dm-threads-v1.json"

    struct Snapshot: Codable {
        let agentName: String
        var inbound: [CoordMessage]
        var outbound: [CoordMessage]
    }

    static func load(for agentName: String) -> (inbound: [CoordMessage], outbound: [CoordMessage]) {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.agentName == agentName else {
            return ([], [])
        }
        return (snapshot.inbound, snapshot.outbound)
    }

    static func save(
        agentName: String,
        inbound: [CoordMessage],
        outbound: [CoordMessage]
    ) {
        let snapshot = Snapshot(agentName: agentName, inbound: inbound, outbound: outbound)
        guard let url = fileURL(),
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[DMThreadPersistence] save failed: \(error)")
        }
    }

    private static func fileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SynthesisArc", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}