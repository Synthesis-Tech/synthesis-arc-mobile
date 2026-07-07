import SwiftUI

/// Blackboard list column — selection drives entry inspector.
struct BlackboardCommandCenterView: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var fleetService: FleetService
    @State private var searchText = ""

    private var filteredEntries: [BlackboardEntry] {
        var entries = fleetService.blackboard
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.value.localizedCaseInsensitiveContains(searchText)
            }
        }
        return entries.sorted { $0.updatedAtUnixMs > $1.updatedAtUnixMs }
    }

    var body: some View {
        List(filteredEntries, selection: keySelection) { entry in
            Button {
                commandCenterState.selectBlackboardKey(entry.key)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.key)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    Text(entry.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                commandCenterState.selectedBlackboardKey == entry.key
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search keys or values")
        .navigationTitle("Blackboard")
        .refreshable { await fleetService.refresh() }
    }

    private var keySelection: Binding<String?> {
        Binding(
            get: { commandCenterState.selectedBlackboardKey },
            set: { commandCenterState.selectBlackboardKey($0) }
        )
    }
}

struct BlackboardInspectorPane: View {
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var fleetService: FleetService

    private var entry: BlackboardEntry? {
        guard let key = commandCenterState.selectedBlackboardKey else { return nil }
        return fleetService.blackboard.first { $0.key == key }
    }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(entry.key)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                        Label(entry.updatedAt, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.value)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select an Entry",
                    systemImage: "list.clipboard",
                    description: Text("Tap a blackboard key to inspect its value.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}