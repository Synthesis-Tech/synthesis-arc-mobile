import SwiftUI

/// Multi-line message input with @-mention autocomplete. macOS: Return sends, ⇧Return newline, Tab completes.
struct GrowingMessageComposer: View {
    @Binding var text: String
    let placeholder: String
    var mentionCandidates: [String] = []
    var onSend: () -> Void

    @FocusState private var isFocused: Bool
    @State private var selectedMentionIndex = 0

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeQuery: MentionActiveQuery? {
        AgentMentionAutocomplete.activeQuery(in: text)
    }

    private var suggestionList: [String] {
        guard activeQuery != nil else { return [] }
        return AgentMentionAutocomplete.filteredCandidates(
            query: activeQuery?.partial ?? "",
            from: mentionCandidates
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if !suggestionList.isEmpty {
                    mentionSuggestionList
                }

                HStack(alignment: .bottom, spacing: 6) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...8)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .focused($isFocused)
                        .onChange(of: text) { _, _ in
                            selectedMentionIndex = 0
                        }
                        #if os(macOS)
                        .onKeyPress(phases: .down) { press in
                            if press.key == .tab, !suggestionList.isEmpty {
                                let index = min(selectedMentionIndex, suggestionList.count - 1)
                                completeMention(suggestionList[index])
                                return .handled
                            }
                            if press.key == .upArrow, !suggestionList.isEmpty {
                                selectedMentionIndex = max(0, selectedMentionIndex - 1)
                                return .handled
                            }
                            if press.key == .downArrow, !suggestionList.isEmpty {
                                selectedMentionIndex = min(suggestionList.count - 1, selectedMentionIndex + 1)
                                return .handled
                            }
                            guard press.key == .return else { return .ignored }
                            if press.modifiers.contains(.shift) {
                                return .ignored
                            }
                            guard canSend else { return .handled }
                            onSend()
                            return .handled
                        }
                        #endif

                    if !mentionCandidates.isEmpty {
                        Menu {
                            ForEach(mentionCandidates, id: \.self) { agent in
                                Button {
                                    text = AgentMentionAutocomplete.insertMention(into: text, agentName: agent)
                                } label: {
                                    Label(
                                        AgentMentionAutocomplete.displayLabel(for: agent),
                                        systemImage: "at"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "at")
                                .font(.body)
                                .foregroundStyle(.blue)
                                .padding(6)
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("Mention agent")
                    }
                }

                #if os(macOS)
                Text(mentionHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                #endif
            }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(!canSend)
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: .command)
            #endif
        }
    }

    private var mentionHint: String {
        if suggestionList.isEmpty {
            return "Return to send · Shift-Return for new line · @ to mention"
        }
        return "Tab to complete mention · ↑↓ to choose"
    }

    private var mentionSuggestionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestionList.prefix(8).enumerated()), id: \.element) { index, agent in
                    Button {
                        completeMention(agent)
                    } label: {
                        HStack {
                            Text(AgentMentionAutocomplete.displayLabel(for: agent))
                                .font(.subheadline.bold())
                            Spacer()
                            Text("@\(agent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == selectedMentionIndex ? Color.blue.opacity(0.12) : Color.clear)
                    }
                    .buttonStyle(.plain)

                    if index < min(suggestionList.count, 8) - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    private func completeMention(_ agentName: String) {
        guard let query = activeQuery else { return }
        text = AgentMentionAutocomplete.complete(text: text, query: query, agentName: agentName)
        selectedMentionIndex = 0
        isFocused = true
    }
}