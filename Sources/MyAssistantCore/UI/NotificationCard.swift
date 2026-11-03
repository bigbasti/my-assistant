import SwiftUI

public struct NotificationCard: View {
    let item: AssistantNotification
    let onOpen: () -> Void
    let onDone: () -> Void
    let onSnooze: (SnoozeOption) -> Void
    @State private var showSnooze = false

    public init(item: AssistantNotification, onOpen: @escaping () -> Void,
                onDone: @escaping () -> Void, onSnooze: @escaping (SnoozeOption) -> Void) {
        self.item = item; self.onOpen = onOpen; self.onDone = onDone; self.onSnooze = onSnooze
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.kind.icon).foregroundStyle(item.kind.color)
                .frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.sender).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(relativeTime(from: item.surfacedAt, now: ctx.date))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(item.title).font(.subheadline).lineLimit(1)
                Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            VStack(spacing: 8) {
                Button { showSnooze = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Snooze")
                    .popover(isPresented: $showSnooze) {
                        SnoozeSheet(firstSurfacedAt: item.firstSurfacedAt) { o in
                            showSnooze = false; onSnooze(o)
                        }
                    }
                Button(action: onDone) { Image(systemName: "checkmark.circle") }.help("Done")
            }
            .buttonStyle(.plain).font(.title3)
        }
        .padding(.vertical, 10).padding(.trailing, 10).padding(.leading, 14)
        .contentShape(.rect(cornerRadius: 12))
        .glassEffect(.regular.tint(item.kind.color.opacity(0.18)), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { AccentEdge(color: item.kind.color, cornerRadius: 12) }
    }
}

/// A 4 pt accent stripe on the leading edge that follows the card's rounded corners.
struct AccentEdge: View {
    let color: Color
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .mask(alignment: .leading) { Rectangle().frame(width: 4) }
            .allowsHitTesting(false)
    }
}
