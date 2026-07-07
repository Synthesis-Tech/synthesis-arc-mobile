import SwiftUI

/// Compact reply chrome — single-line header, no quote block (preview is in the thread).
struct ReplyComposerBanner: View {
    let context: ReplyContext
    var showChannelTag: Bool = true
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(context.prefersDirectMessage ? .blue : .orange)

            Text("Reply to \(context.compactSenderLabel)")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            deliveryBadge

            Text(context.compactReference)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if showChannelTag, let channel = context.channelName {
                Text("#\(channel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var deliveryBadge: some View {
        Text(context.deliveryLabel.uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(context.prefersDirectMessage ? .blue : .orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                (context.prefersDirectMessage ? Color.blue : Color.orange).opacity(0.14)
            )
            .clipShape(Capsule())
    }
}