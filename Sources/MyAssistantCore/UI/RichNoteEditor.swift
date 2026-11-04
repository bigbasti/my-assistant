import SwiftUI

/// Pure helpers for the List button.
enum NoteFormatting {
    static let bullet = "• "

    /// Character offsets of the starts of all lines touched by [from, to].
    static func lineStarts(in text: String, from: Int, to: Int) -> [Int] {
        let chars = Array(text)
        let lo = max(0, min(from, chars.count)), hi = max(lo, min(to, chars.count))
        var start = lo
        while start > 0, chars[start - 1] != "\n" { start -= 1 }
        var starts = [start]
        var i = start
        while i < hi {
            if chars[i] == "\n", i + 1 <= chars.count { starts.append(i + 1) }
            i += 1
        }
        return starts
    }

    static func allBulleted(in text: String, starts: [Int]) -> Bool {
        let chars = Array(text)
        return starts.allSatisfy { s in
            s + 1 < chars.count && String(chars[s..<s + 2]) == bullet
        }
    }
}

/// 10-line rich-text editor with a formatting toolbar acting on the selection.
struct RichNoteEditor: View {
    @Binding var text: AttributedString
    let done: () -> Void
    @State private var selection = AttributedTextSelection()
    @State private var showLink = false
    @State private var linkText = "https://"
    @Environment(\.fontResolutionContext) private var fontContext
    @FocusState private var focused: Bool

    private static let sizes: [(String, CGFloat)] = [("Small", 11), ("Normal", 13), ("Large", 17), ("Title", 22)]
    private static let colors: [(String, Color?)] = [
        ("Default", nil), ("Red", .red), ("Orange", .orange), ("Green", .green), ("Blue", .blue), ("Purple", .purple),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolbar
            TextEditor(text: $text, selection: $selection)
                .font(.body)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($focused)
                .onAppear { DispatchQueue.main.async { focused = true } }
                .padding(4)
                .frame(height: NSFont.preferredFont(forTextStyle: .body).boundingRectForFont.height * 10 + 8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { toggleBold() } label: { Image(systemName: "bold") }.help("Bold")
            Button { toggleUnderline() } label: { Image(systemName: "underline") }.help("Underline")
            Menu {
                ForEach(Self.colors, id: \.0) { name, color in
                    Button { apply { $0.foregroundColor = color } } label: {
                        Label(name, systemImage: "circle.fill").foregroundStyle(color ?? .primary)
                    }
                }
            } label: { Image(systemName: "paintpalette") }
            .menuStyle(.button).menuIndicator(.hidden).fixedSize().help("Color")
            Menu {
                ForEach(Self.sizes, id: \.0) { name, size in
                    Button(name) { apply { $0.font = .system(size: size) } }
                }
            } label: { Image(systemName: "textformat.size") }
            .menuStyle(.button).menuIndicator(.hidden).fixedSize().help("Size")
            Button { showLink = true } label: { Image(systemName: "link") }
                .help("Link")
                .popover(isPresented: $showLink) { linkPopover }
            Button { toggleList() } label: { Image(systemName: "list.bullet") }.help("List")
            Spacer()
            Button("Done", action: done).buttonStyle(.glassProminent).controlSize(.small)
        }
        .buttonStyle(.plain)
    }

    private var linkPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link selected text to").font(.caption).foregroundStyle(.secondary)
            TextField("https://", text: $linkText).textFieldStyle(.roundedBorder).frame(width: 240)
                .onSubmit(applyLink)
            HStack {
                Button("Remove link") { apply { $0.link = nil }; showLink = false }.buttonStyle(.glass)
                Spacer()
                Button("Apply", action: applyLink).buttonStyle(.glassProminent)
            }
        }
        .padding(12)
    }

    private func apply(_ change: (inout AttributeContainer) -> Void) {
        text.transformAttributes(in: &selection, body: change)
    }

    private func toggleBold() {
        let current = selection.typingAttributes(in: text).font ?? .body
        let isBold = current.resolve(in: fontContext).isBold
        apply { $0.font = ($0.font ?? .body).bold(!isBold) }
    }

    private func toggleUnderline() {
        let on = selection.typingAttributes(in: text).underlineStyle != nil
        apply { $0.underlineStyle = on ? nil : .single }
    }

    private func applyLink() {
        let trimmed = linkText.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), url.scheme != nil { apply { $0.link = url } }
        showLink = false
    }

    private func toggleList() {
        let plain = String(text.characters)
        let (from, to) = selectedOffsets(plain: plain)
        let starts = NoteFormatting.lineStarts(in: plain, from: from, to: to)
        let remove = NoteFormatting.allBulleted(in: plain, starts: starts)
        // Edit from the last line backwards so earlier offsets stay valid.
        for s in starts.reversed() {
            let idx = text.characters.index(text.startIndex, offsetBy: s)
            if remove {
                let end = text.characters.index(idx, offsetBy: NoteFormatting.bullet.count)
                text.removeSubrange(idx..<end)
            } else {
                text.insert(AttributedString(NoteFormatting.bullet), at: idx)
            }
        }
        selection = AttributedTextSelection()
    }

    private func selectedOffsets(plain: String) -> (Int, Int) {
        func offset(_ i: AttributedString.Index) -> Int { text.characters.distance(from: text.startIndex, to: i) }
        switch selection.indices(in: text) {
        case .insertionPoint(let i):
            let o = offset(i); return (o, o)
        case .ranges(let set):
            let lo = set.ranges.map { offset($0.lowerBound) }.min() ?? 0
            let hi = set.ranges.map { offset($0.upperBound) }.max() ?? lo
            return (lo, hi)
        }
    }
}
