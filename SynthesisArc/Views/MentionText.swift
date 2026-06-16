import SwiftUI

/// Renders message text with `@agent-name` mentions highlighted in blue/bold.
struct MentionText: View {
    let content: String
    var font: Font = .callout
    var mentionColor: Color = .blue

    var body: some View {
        styledText
            .font(font)
    }

    private var styledText: Text {
        MentionParser.segments(in: content).reduce(Text("")) { partial, segment in
            switch segment {
            case .plain(let text):
                partial + Text(text)
            case .mention(let text):
                partial + Text(text)
                    .foregroundStyle(mentionColor)
                    .bold()
            }
        }
    }
}

// MARK: - Mention Parsing

enum MentionSegment: Equatable {
    case plain(String)
    case mention(String)
}

enum MentionParser {
    /// Matches `@kenji-okafor` style agent names (kebab-case).
    private static let pattern = try! NSRegularExpression(
        pattern: #"@([a-zA-Z][a-zA-Z0-9-]*)"#,
        options: []
    )

    static func segments(in text: String) -> [MentionSegment] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = pattern.matches(in: text, options: [], range: fullRange)

        guard !matches.isEmpty else {
            return [.plain(text)]
        }

        var result: [MentionSegment] = []
        var cursor = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > cursor {
                let plainRange = NSRange(
                    location: cursor,
                    length: matchRange.location - cursor
                )
                let plain = nsText.substring(with: plainRange)
                if !plain.isEmpty {
                    result.append(.plain(plain))
                }
            }
            let mention = nsText.substring(with: matchRange)
            result.append(.mention(mention))
            cursor = matchRange.location + matchRange.length
        }

        if cursor < nsText.length {
            let tail = nsText.substring(from: cursor)
            if !tail.isEmpty {
                result.append(.plain(tail))
            }
        }

        return result
    }
}