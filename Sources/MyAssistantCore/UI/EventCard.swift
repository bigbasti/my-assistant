import SwiftUI

public struct EventCard: View {
    let event: CalendarEvent
    let onOpen: () -> Void
    let onJoin: () -> Void
    let onDismiss: () -> Void

    public init(event: CalendarEvent, onOpen: @escaping () -> Void,
                onJoin: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.event = event; self.onOpen = onOpen; self.onJoin = onJoin; self.onDismiss = onDismiss
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            content(CountdownPhase.phase(start: event.start, now: ctx.date))
        }
    }

    private func isRed(_ p: CountdownPhase) -> Bool {
        switch p { case .warning, .pulsing, .started: true; default: false }
    }

    private func badge(_ p: CountdownPhase) -> String? {
        switch p {
        case .countdown(let r), .warning(let r), .pulsing(let r): countdownLabel(r)
        case .started: "now"
        case .idle: nil
        }
    }

    @ViewBuilder private func tint(_ p: CountdownPhase) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if case .pulsing = p {
            shape.fill(Color.red.opacity(0.35)).phaseAnimator([1.0, 0.35]) { v, f in
                v.opacity(f)
            } animation: { _ in .easeInOut(duration: 0.9) }
        } else if isRed(p) {
            shape.fill(Color.red.opacity(0.35))
        } else {
            Color.clear
        }
    }

    private func content(_ p: CountdownPhase) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(timeRangeLabel(start: event.start, end: event.end))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let b = badge(p) {
                        Text(b).font(.caption.monospacedDigit().bold())
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(isRed(p) ? Color.red : Color.secondary.opacity(0.3), in: .capsule)
                            .foregroundStyle(isRed(p) ? .white : .primary)
                    }
                }
                Text(event.subject).font(.headline).lineLimit(2)
                if let l = event.location, !l.isEmpty {
                    Label(l, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let o = event.organizer, !o.isEmpty {
                    Label(o, systemImage: "person").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            VStack(spacing: 8) {
                Button(action: onDismiss) { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain).font(.title3).help("Dismiss")
                if event.joinURL != nil {
                    Button(action: onJoin) {
                        Image(systemName: "video.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 26)
                            .background(SourceKind.calendar.color, in: .capsule)
                    }
                    .buttonStyle(.plain).help("Join meeting")
                }
            }
        }
        .padding(.vertical, 10).padding(.trailing, 10).padding(.leading, 14)
        .contentShape(.rect(cornerRadius: 12, style: .continuous))
        .background { tint(p) }
        .glassEffect(.regular.tint(isRed(p) ? Color.red.opacity(0.2) : SourceKind.calendar.color.opacity(0.12)),
                     in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { AccentEdge(color: isRed(p) ? .red : SourceKind.calendar.color, cornerRadius: 12) }
        .animation(.easeInOut(duration: 0.4), value: isRed(p))
    }
}
