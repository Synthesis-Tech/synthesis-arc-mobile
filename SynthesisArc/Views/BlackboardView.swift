import SwiftUI

/// Blackboard tab — live key-value state view
struct BlackboardView: View {
    @EnvironmentObject var fleetService: FleetService
    @State private var searchText = ""
    @State private var filterPrefix = ""

    private var filteredEntries: [BlackboardEntry] {
        var entries = fleetService.blackboard
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.value.localizedCaseInsensitiveContains(searchText)
            }
        }
        if !filterPrefix.isEmpty {
            entries = entries.filter { $0.key.hasPrefix(filterPrefix) }
        }
        return entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Group entries by key prefix (before first ".")
    private var groupedEntries: [(String, [BlackboardEntry])] {
        let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
            if let dotIndex = entry.key.firstIndex(of: ".") {
                return String(entry.key[..<dotIndex])
            }
            return entry.key
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedEntries, id: \.0) { prefix, entries in
                    Section(prefix) {
                        ForEach(entries) { entry in
                            BlackboardEntryRow(entry: entry)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search keys or values")
            .navigationTitle("Blackboard")
            .refreshable {
                await fleetService.refresh()
            }
        }
    }
}

struct BlackboardEntryRow: View {
    let entry: BlackboardEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shortKey)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))

                Spacer()

                Text(formatTime(entry.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 2)
                .textSelection(.enabled)
        }
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    /// Key without the prefix (already shown in section header)
    private var shortKey: String {
        if let dotIndex = entry.key.firstIndex(of: ".") {
            return String(entry.key[entry.key.index(after: dotIndex)...])
        }
        return entry.key
    }

    private func formatTime(_ iso: String) -> String {
        if let tIndex = iso.firstIndex(of: "T"),
           let dotIndex = iso.firstIndex(of: ".") ?? iso.firstIndex(of: "+") {
            let timeStr = iso[iso.index(after: tIndex)..<dotIndex]
            return String(timeStr.prefix(5))
        }
        return iso.suffix(8).description
    }
}
