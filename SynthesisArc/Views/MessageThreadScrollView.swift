import SwiftUI

/// Scrollable message list pinned to the bottom with a “N new” jump pill when scrolled up.
struct MessageThreadScrollView<Message: Identifiable, Row: View>: View where Message.ID == UInt64 {
    let messages: [Message]
    @ViewBuilder let row: (Message) -> Row

    @State private var scrollPosition: ThreadScrollPosition?
    @State private var isPinnedToBottom = true
    @State private var pendingNewCount = 0
    @State private var anchorMessageId: UInt64?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(messages) { message in
                    row(message)
                        .id(ThreadScrollPosition.message(message.id))
                }
                Color.clear
                    .frame(height: 1)
                    .id(ThreadScrollPosition.bottom)
            }
            .padding()
            .scrollTargetLayout()
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition(id: $scrollPosition, anchor: .bottom)
        .overlay(alignment: .bottom) {
            if pendingNewCount > 0 {
                newMessagesPill
            }
        }
        .onChange(of: scrollPosition) { _, position in
            updatePinnedState(for: position)
        }
        .onChange(of: messages.map(\.id)) { _, _ in
            handleMessagesUpdate()
        }
        .onAppear {
            jumpToBottom()
        }
    }

    private var newMessagesPill: some View {
        Button {
            jumpToBottom()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                Text(pendingNewCount == 1 ? "1 new message" : "\(pendingNewCount) new messages")
                    .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.blue)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeOut(duration: 0.2), value: pendingNewCount)
    }

    private func updatePinnedState(for position: ThreadScrollPosition?) {
        let atBottom: Bool = {
            guard let position else { return true }
            switch position {
            case .bottom:
                return true
            case .message(let id):
                return id == messages.last?.id
            }
        }()

        if atBottom {
            isPinnedToBottom = true
            pendingNewCount = 0
            anchorMessageId = nil
        } else if isPinnedToBottom {
            isPinnedToBottom = false
            anchorMessageId = messages.last?.id
        }
    }

    private func handleMessagesUpdate() {
        if isPinnedToBottom {
            jumpToBottom(animated: false)
            return
        }

        guard let anchor = anchorMessageId else {
            pendingNewCount = messages.count
            return
        }

        if let index = messages.firstIndex(where: { $0.id == anchor }) {
            pendingNewCount = max(0, messages.count - index - 1)
        } else {
            pendingNewCount = messages.count
        }
    }

    private func jumpToBottom(animated: Bool = true) {
        isPinnedToBottom = true
        pendingNewCount = 0
        anchorMessageId = nil
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                scrollPosition = .bottom
            }
        } else {
            scrollPosition = .bottom
        }
    }
}

private enum ThreadScrollPosition: Hashable {
    case message(UInt64)
    case bottom
}