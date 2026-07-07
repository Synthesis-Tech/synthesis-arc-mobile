import SwiftUI

/// Scrollable message list — intentionally simple to avoid scrollPosition layout loops.
struct MessageThreadScrollView<Message: Identifiable, Row: View>: View where Message.ID == UInt64 {
    let messages: [Message]
    @ViewBuilder let row: (Message) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(messages) { message in
                    row(message)
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
    }
}