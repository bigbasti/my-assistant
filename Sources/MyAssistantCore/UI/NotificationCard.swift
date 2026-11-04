import SwiftUI

public struct NotificationCard: View {
    let item: AssistantNotification
    let onOpen: () -> Void
    let onDone: () -> Void
    let onSnooze: (SnoozeOption) -> Void
    /// Only set for mail cards; returns a message to show when nothing was deleted.
    let onDelete: (() async -> String?)?
    let onCreateTodo: (() -> Void)?
    @State private var showSnooze = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

    public init(item: AssistantNotification, onOpen: @escaping () -> Void,
                onDone: @escaping () -> Void, onSnooze: @escaping (SnoozeOption) -> Void,
                onCreateTodo: (() -> Void)? = nil,
                onDelete: (() async -> String?)? = nil) {
        self.item = item; self.onOpen = onOpen; self.onDone = onDone; self.onSnooze = onSnooze
        self.onDelete = onDelete; self.onCreateTodo = onCreateTodo
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
                if let deleteError {
                    Label(deleteError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .transition(.opacity)
                }
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
                if onDelete != nil {
                    Group {
                        if deleting {
                            ProgressView().controlSize(.small).frame(width: 20, height: 20)
                        } else {
                            Button { confirmDelete = true } label: { Image(systemName: "trash") }
                                .help("Delete mail")
                                .popover(isPresented: $confirmDelete) { deleteConfirmation }
                        }
                    }
                }
            }
            .buttonStyle(.plain).font(.title3)
        }
        .padding(.vertical, 10).padding(.trailing, 10).padding(.leading, 14)
        .contentShape(.rect(cornerRadius: 12))
        .glassEffect(.regular.tint(item.kind.color.opacity(0.18)), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { AccentEdge(color: item.kind.color, cornerRadius: 12) }
        .contextMenu {
            if let onCreateTodo {
                Button(action: onCreateTodo) { Label("Create To Do", systemImage: "checklist") }
            }
        }
        .background {
            // Re-evaluated every 30 s so the glow switches off on its own after 10 minutes.
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                if isFreshMessage(surfacedAt: item.surfacedAt, now: ctx.date) {
                    FreshGlow(color: item.kind.color, cornerRadius: 12)
                }
            }
        }
    }

    private var deleteConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete this mail?").font(.headline)
            Text("It moves to Deleted Items in your mailbox.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { confirmDelete = false }.buttonStyle(.glass)
                Spacer()
                Button("Delete", role: .destructive) {
                    confirmDelete = false
                    guard let onDelete else { return }
                    deleting = true
                    Task {
                        let message = await onDelete()
                        deleting = false
                        withAnimation { deleteError = message }
                        if message != nil {
                            try? await Task.sleep(for: .seconds(8))
                            withAnimation { deleteError = nil }
                        }
                    }
                }
                .buttonStyle(.glassProminent).tint(.red)
            }
        }
        .padding(14).frame(width: 240)
    }
}

/// Soft, slowly breathing halo plus outline in the source color for new messages.
struct FreshGlow: View {
    let color: Color
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .strokeBorder(color.opacity(0.9), lineWidth: 1.5)
            .background(shape.fill(color.opacity(0.25)))
            .shadow(color: color.opacity(0.8), radius: 8)
            .phaseAnimator([0.45, 1.0]) { v, f in v.opacity(f) } animation: { _ in .easeInOut(duration: 1.8) }
            .allowsHitTesting(false)
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
