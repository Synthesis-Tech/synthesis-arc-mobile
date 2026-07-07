import SwiftUI

/// Fleet grid for iPad command center — selection drives the inspector column.
struct FleetCommandCenterView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var commandCenterState: CommandCenterState
    @EnvironmentObject var fleetService: FleetService
    @AppStorage(FleetWatchlist.storageKey) private var watchlistRaw = ""
    @State private var searchText = ""
    @State private var collapsedSections: Set<String> = []
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 10)]
        }
        return [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]
    }

    private var watchlist: Set<String> {
        FleetWatchlist.decode(watchlistRaw)
    }

    private var sections: [FleetSection] {
        fleetService.fleetSections(searchText: searchText, watchlist: watchlist)
    }

    private var attentionPeers: [Peer] {
        fleetService.peersNeedingAttention(watchlist: watchlist)
            .filter { $0.matchesFleetSearch(searchText) }
    }

    var body: some View {
        ScrollView {
            if fleetService.isLoading && fleetService.peers.isEmpty {
                ProgressView("Loading fleet...")
                    .padding(.top, 60)
            } else if let error = fleetService.error, fleetService.peers.isEmpty {
                errorState(error)
            } else {
                fleetHeader
                searchBar

                if sections.isEmpty && attentionPeers.isEmpty {
                    emptySearchState
                } else {
                    if !attentionPeers.isEmpty {
                        needsAttentionSection
                    }
                    fleetSections
                }
            }
        }
        .navigationTitle("Fleet")
        .refreshable {
            await fleetService.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await fleetService.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - States

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await fleetService.refresh() }
            }
        }
        .padding(.top, 60)
    }

    private var emptySearchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No agents match \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Fleet Header

    private var fleetHeader: some View {
        HStack(spacing: 20) {
            statBadge(count: fleetService.peers.count, label: "Online", color: .green)
            statBadge(
                count: fleetService.peers.filter { $0.statusColor == .green }.count,
                label: "Active",
                color: .blue
            )
            statBadge(count: fleetService.exceptionCount, label: "Attention", color: .orange)
        }
        .padding()
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search agents", text: $searchText)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Needs Attention

    private var needsAttentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Needs Attention")
                    .font(.system(.subheadline, weight: .semibold))
                Text("\(attentionPeers.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(attentionPeers) { peer in
                    let score = fleetService.signalScore(for: peer, watchlist: watchlist)
                    fleetAgentButton(
                        peer: peer,
                        needsAttention: true,
                        attentionScore: score,
                        isPinned: watchlist.contains(peer.agentName),
                        onTogglePin: { FleetWatchlist.toggle(peer.agentName, in: &watchlistRaw) },
                        onQuickDM: { commandCenterState.openFleetDM(agentName: peer.agentName) },
                        onQuickMention: { FleetClipboard.copy("@\(peer.agentName)") }
                    )
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Sections

    private var fleetSections: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                CommandCenterFleetSectionView(
                    section: section,
                    columns: columns,
                    isCollapsed: collapsedSections.contains(section.id),
                    selectedAgentName: commandCenterState.selectedAgentName,
                    watchlist: watchlist,
                    onSelect: { commandCenterState.selectAgent($0) },
                    onToggleCollapse: { toggleSection(section.id) },
                    onTogglePin: { FleetWatchlist.toggle($0, in: &watchlistRaw) },
                    onQuickDM: { commandCenterState.openFleetDM(agentName: $0.agentName) },
                    onQuickMention: { FleetClipboard.copy("@\($0.agentName)") }
                )
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    private func toggleSection(_ id: String) {
        if collapsedSections.contains(id) {
            collapsedSections.remove(id)
        } else {
            collapsedSections.insert(id)
        }
    }

    @ViewBuilder
    private func fleetAgentButton(
        peer: Peer,
        needsAttention: Bool = false,
        attentionScore: Int = 0,
        isPinned: Bool,
        onTogglePin: @escaping () -> Void,
        onQuickDM: @escaping () -> Void,
        onQuickMention: @escaping () -> Void
    ) -> some View {
        let isSelected = commandCenterState.selectedAgentName == peer.agentName
        Button {
            commandCenterState.selectAgent(peer.agentName)
        } label: {
            AgentCard(
                peer: peer,
                isPinned: isPinned,
                needsAttention: needsAttention,
                attentionScore: attentionScore,
                onTogglePin: onTogglePin,
                onQuickDM: onQuickDM,
                onQuickMention: onQuickMention
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: isSelected ? 2.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section (command center variant)

private struct CommandCenterFleetSectionView: View {
    let section: FleetSection
    let columns: [GridItem]
    let isCollapsed: Bool
    let selectedAgentName: String?
    let watchlist: Set<String>
    let onSelect: (String) -> Void
    let onToggleCollapse: () -> Void
    let onTogglePin: (String) -> Void
    var onQuickDM: (Peer) -> Void = { _ in }
    var onQuickMention: (Peer) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggleCollapse) {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    if section.id == "watchlist" {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Text(section.title)
                        .font(.system(.subheadline, weight: .semibold))

                    Text("\(section.peers.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if section.exceptionCount > 0 {
                        exceptionBadge(count: section.exceptionCount)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(section.peers) { peer in
                        let isSelected = selectedAgentName == peer.agentName
                        Button {
                            onSelect(peer.agentName)
                        } label: {
                            AgentCard(
                                peer: peer,
                                isPinned: watchlist.contains(peer.agentName),
                                onTogglePin: { onTogglePin(peer.agentName) },
                                onQuickDM: { onQuickDM(peer) },
                                onQuickMention: { onQuickMention(peer) }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor : Color.clear,
                                        lineWidth: isSelected ? 2.5 : 0
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func exceptionBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange)
            .clipShape(Capsule())
            .accessibilityLabel("\(count) exceptions")
    }
}