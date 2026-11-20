import SwiftUI

// MARK: - Flags
// The one shared word on flags: the parser that splits the leading
// country emoji off a panel-given name, and the renderer that wears it
// in either the bundled Twemoji face or the platform's own emoji font.

/// The leading-flag split, ported from the Android client's
/// `splitLeadingFlag`: consumes every consecutive regional-indicator
/// pair at the front of the name (after any leading whitespace) and
/// hands back the flags alone in the icon slot, the rest as the title.
/// A name without a leading flag keeps itself whole.
enum ChumpyFlag {
    static func splitLeading(_ raw: String) -> (flag: String?, title: String) {
        let scalars = raw.unicodeScalars
        var index = scalars.startIndex
        // Leading whitespace never counts against the flag.
        while index < scalars.endIndex, scalars[index].properties.isWhitespace {
            index = scalars.index(after: index)
        }
        let flagStart = index
        var flagEnd = index
        var pairs = 0
        while scalars.index(after: flagEnd) < scalars.endIndex {
            let first = scalars[flagEnd]
            let second = scalars[scalars.index(after: flagEnd)]
            guard (0x1F1E6...0x1F1FF).contains(first.value),
                  (0x1F1E6...0x1F1FF).contains(second.value)
            else { break }
            flagEnd = scalars.index(after: scalars.index(after: flagEnd))
            pairs += 1
        }
        guard pairs > 0 else { return (nil, raw) }
        let flag = String(String.UnicodeScalarView(scalars[flagStart..<flagEnd]))
        let title = String(String.UnicodeScalarView(scalars[flagEnd...]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (flag, title)
    }
}

/// The flag glyph, styled by the Interface page's own toggle: Twemoji's
/// bundled font when it's on, the platform's emoji font when it's off.
/// The toggle is read here directly, so every flag in the app follows
/// the one switch without a prop threaded through every screen.
struct FlagView: View {
    let flag: String
    var fontSize: CGFloat = 20

    @AppStorage("twemojiFlags") private var twemojiFlags = true

    var body: some View {
        Text(flag)
            .font(
                twemojiFlags
                    ? .custom("Twemoji Mozilla", size: fontSize)
                    : .system(size: fontSize)
            )
    }
}
