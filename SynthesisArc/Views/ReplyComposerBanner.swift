import SwiftUI

/// Slack-style reply bar — shows who/what you're replying to plus a content snippet and message ref.
struct ReplyComposerBanner: View {
    let context: ReplyContext
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.blue)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)

                    Text("Replying to \(context.senderLabel)")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)

                    Text(context.referenceTag)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)

                    if let channel = context.channelName {
                        Text("#\(channel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(context.truncatedPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.08))
    }
}