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
        if case .pulsing = p {
            Color.red.opacity(0.3).phaseAnimator([1.0, 0.55]) { v, f in
                v.opacity(f).scaleEffect(f == 1.0 ? 1.0 : 0.97)
            } animation: { _ in .easeInOut(duration: 0.6) }
        } else if isRed(p) {
            Color.red.opacity(0.3)
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
                    Button(action: onJoin) { Label("Join", systemImage: "video.fill").labelStyle(.iconOnly) }
                        .buttonStyle(.glassProminent).tint(SourceKind.calendar.color).help("Join")
                }
            }
        }
        .padding(8).padding(.leading, 4)
        .background { tint(p) }
        .glassEffect(.regular.tint(isRed(p) ? Color.red.opacity(0.25) : SourceKind.calendar.color.opacity(0.15)),
                     in: .rect(cornerRadius: 12))
    }
}
