import SwiftUI

/// Fleet View — department-grouped agent grid with search and watchlist
struct FleetView: View {
    @EnvironmentObject var fleetService: FleetService
    @EnvironmentObject var commandCenterState: CommandCenterState
    @AppStorage(FleetWatchlist.storageKey) private var watchlistRaw = ""
    @State private var searchText = ""
    @State private var collapsedSections: Set<String> = []
    @State private var quickDMPeer: Peer?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

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
        NavigationStack {
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
            .sheet(item: $quickDMPeer) { peer in
                NavigationStack {
                    DMView(peer: peer)
                }
            }
            .onChange(of: commandCenterState.deepLinkEpoch) { _, _ in
                openDeepLinkedFleetDMIfNeeded()
            }
        }
    }

    private func openDeepLinkedFleetDMIfNeeded() {
        guard commandCenterState.phoneTab == .fleet,
              commandCenterState.fleetDetailMode == .dm,
              let agentName = commandCenterState.selectedAgentName else { return }
        quickDMPeer = fleetService.peers.first { $0.agentName == agentName }
            ?? Peer(
                agentName: agentName,
                pid: nil,
                cwd: nil,
                gitRoot: nil,
                summary: nil,
                status: .offline
            )
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
            statBadge(
                count: fleetService.peers.count,
                label: "Online",
                color: .green
            )
            statBadge(
                count: fleetService.peers.filter { $0.statusColor == .green }.count,
                label: "Active",
                color: .blue
            )
            statBadge(
                count: fleetService.exceptionCount,
                label: "Attention",
                color: .orange
            )
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
                    NavigationLink(destination: AgentDetailView(peer: peer)) {
                        AgentCard(
                            peer: peer,
                            isPinned: watchlist.contains(peer.agentName),
                            needsAttention: true,
                            attentionScore: score,
                            onTogglePin: {
                                FleetWatchlist.toggle(peer.agentName, in: &watchlistRaw)
                            },
                            onQuickDM: { quickDMPeer = peer },
                            onQuickMention: {
                                FleetClipboard.copy("@\(peer.agentName)")
                            }
                        )
                    }
                    .buttonStyle(.plain)
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
                FleetSectionView(
                    section: section,
                    columns: columns,
                    isCollapsed: collapsedSections.contains(section.id),
                    watchlist: watchlist,
                    onToggleCollapse: { toggleSection(section.id) },
                    onTogglePin: { agentName in
                        FleetWatchlist.toggle(agentName, in: &watchlistRaw)
                    },
                    onQuickDM: { quickDMPeer = $0 },
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
}

// MARK: - Fleet Section View

private struct FleetSectionView: View {
    let section: FleetSection
    let columns: [GridItem]
    let isCollapsed: Bool
    let watchlist: Set<String>
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
                        NavigationLink(destination: AgentDetailView(peer: peer)) {
                            AgentCard(
                                peer: peer,
                                isPinned: watchlist.contains(peer.agentName),
                                onTogglePin: { onTogglePin(peer.agentName) },
                                onQuickDM: { onQuickDM(peer) },
                                onQuickMention: { onQuickMention(peer) }
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

// MARK: - Agent Card

struct AgentCard: View {
    let peer: Peer
    var isPinned: Bool = false
    var needsAttention: Bool = false
    var attentionScore: Int = 0
    var onTogglePin: (() -> Void)?
    var onQuickDM: (() -> Void)?
    var onQuickMention: (() -> Void)?
    @State private var isHovered = false
    @State private var showQuickActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AgentAvatarView(agentName: peer.agentName, size: 28)
                Text(peer.displayName)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let onTogglePin {
                    Button(action: onTogglePin) {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(isPinned ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPinned ? "Unpin agent" : "Pin agent")
                }
            }

            if let bootState = peer.bootState {
                Text(bootState)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(bootStateColor(bootState))
            }

            if let summary = peer.blackboardStatus ?? peer.summary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(statusBorderColor, lineWidth: needsAttention ? 2 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if showCardQuickActions {
                HStack(spacing: 4) {
                    if let onQuickDM {
                        cardQuickButton(icon: "envelope.fill", tint: .indigo, label: "DM", action: onQuickDM)
                    }
                    if let onQuickMention {
                        cardQuickButton(icon: "at", tint: .blue, label: "Mention", action: onQuickMention)
                    }
                }
                .padding(6)
            }
        }
        #if os(macOS)
        .onHover { isHovered = $0 }
        #else
        .onLongPressGesture(minimumDuration: 0.35) {
            showQuickActions.toggle()
        }
        #endif
        .contextMenu {
            if let onQuickDM {
                Button { onQuickDM() } label: {
                    Label("Send DM", systemImage: "envelope.fill")
                }
            }
            if let onQuickMention {
                Button { onQuickMention() } label: {
                    Label("Copy @\(peer.agentName)", systemImage: "at")
                }
            }
            Button {
                FleetClipboard.copy(peer.agentName)
            } label: {
                Label("Copy agent ID", systemImage: "doc.on.doc")
            }
        }
    }

    private var showCardQuickActions: Bool {
        #if os(iOS)
        return isHovered || showQuickActions
        #else
        return isHovered
        #endif
    }

    private func cardQuickButton(
        icon: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 24)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var cardBackground: some ShapeStyle {
        if needsAttention {
            return AnyShapeStyle(attentionBackgroundColor.opacity(0.15))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var attentionBackgroundColor: Color {
        attentionScore >= 80 ? .red : .orange
    }

    private var statusDotColor: Color {
        switch peer.statusColor {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    private var statusBorderColor: Color {
        if needsAttention {
            return attentionScore >= 80 ? .red.opacity(0.7) : .orange.opacity(0.7)
        }
        if peer.isFleetException {
            return Color.orange.opacity(0.5)
        }
        return statusDotColor.opacity(0.3)
    }

    private func bootStateColor(_ state: String) -> Color {
        switch state {
        case "woke_up": return .green
        case "reconstructed": return .orange
        case "performed": return .yellow
        case "degraded": return .red
        default: return .secondary
        }
    }
}