import SwiftUI

/// Multi-line message input — grows with content (1–8 lines). macOS: Return sends, ⇧Return newline.
struct GrowingMessageComposer: View {
    @Binding var text: String
    let placeholder: String
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .focused($isFocused)
                    #if os(macOS)
                    .onKeyPress(phases: .down) { press in
                        guard press.key == .return else { return .ignored }
                        if press.modifiers.contains(.shift) {
                            return .ignored
                        }
                        guard canSend else { return .handled }
                        onSend()
                        return .handled
                    }
                    #endif

                #if os(macOS)
                Text("Return to send · Shift-Return for new line")
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
}