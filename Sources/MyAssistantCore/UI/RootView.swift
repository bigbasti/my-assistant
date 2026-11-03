import SwiftUI

public struct RootView: View {
    let model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let _ = model.tickCount
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 0) {
                DragGrip()
                VStack(spacing: 8) {
                    messages
                    calendar
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(8)
    }

    private var messages: some View {
        let items = model.notifications.visible
        return VStack(spacing: 8) {
            header("Messages", kinds: [.teams, .mail]) {
                Text("\(items.count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.tint.opacity(0.3), in: .capsule)
            }
            if items.isEmpty {
                ContentUnavailableView("All caught up", systemImage: "tray")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { n in
                            NotificationCard(item: n, onOpen: { model.open(n) },
                                             onDone: { withAnimation { model.notifications.markDone(n.id) } },
                                             onSnooze: { o in withAnimation { model.notifications.snooze(n.id, o) } })
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.smooth, value: items.map(\.id))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var calendar: some View {
        let events = model.events.today
        return VStack(spacing: 8) {
            header("Today", kinds: [.calendar]) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if events.isEmpty {
                ContentUnavailableView("No more events today", systemImage: "calendar")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(events) { e in
                            EventCard(event: e, onOpen: { model.open(e.webLink) },
                                      onJoin: { model.open(e.joinURL) },
                                      onDismiss: { withAnimation { model.events.dismiss(e.id) } })
                            .transition(.opacity)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func header<T: View>(_ title: String, kinds: [SourceKind], @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.title3.bold())
            trailing()
            Spacer()
            ForEach(kinds, id: \.self) { k in
                let (color, tip) = Self.dot(model.status[k])
                Circle().fill(color).frame(width: 8, height: 8).help("\(k.rawValue.capitalized): \(tip)")
            }
        }
        .padding(.horizontal, 8)
    }

    static func dot(_ s: SourceStatus?) -> (Color, String) {
        switch s {
        case .ok: (.green, "OK")
        case .error(let m): (.orange, m)
        case .noAlertsYet: (.green, "No alerts yet")
        case .needsFullDiskAccess: (.orange, "Full Disk Access needed")
        case .needsCalendarAccess: (.orange, "Calendar access needed")
        case .none: (.gray, "—")
        case .disabled: (.gray, "Disabled")
        }
    }
}

// #Preview needs Xcode's PreviewsMacros plugin (absent with Command Line Tools); use this in Xcode.
@MainActor
public func sampleRootView() -> some View {
    let m = AppModel(persistence: Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("preview.json")))
    m.injectSampleData()
    return RootView(model: m).frame(width: 360, height: 700)
}
