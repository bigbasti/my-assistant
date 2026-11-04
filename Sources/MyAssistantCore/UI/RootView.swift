import SwiftUI

public struct RootView: View {
    let model: AppModel
    @State private var todosExpanded = false
    @State private var openTodo: UUID?
    @State private var todoContent: CGFloat = 32
    public init(model: AppModel) { self.model = model }

    /// Height of the To Dos section: 50 % when expanded, otherwise its content (+ header),
    /// capped at 30 % of the panel, or 45 % while a note is open.
    private func todosHeight(_ available: CGFloat) -> CGFloat {
        if todosExpanded { return available * 0.5 }
        let cap = available * (openTodo == nil ? 0.30 : 0.45)
        return min(cap, todoContent + 40)
    }

    public var body: some View {
        let _ = model.tickCount
        VStack(spacing: 0) {
            DragGrip()
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let available = max(0, geo.size.height - spacing * 2)
                let todosH = todosHeight(available)
                let rest = available - todosH
                VStack(spacing: spacing) {
                    messages.frame(height: rest * 2 / 3)
                    TodoSection(model: model, expanded: $todosExpanded, openID: $openTodo, contentHeight: $todoContent)
                        .frame(height: todosH)
                    calendar.frame(height: rest / 3)
                }
                .animation(Self.motion, value: todosH)
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(model.settings.backgroundOpacity * 0.92))
                .animation(.easeInOut(duration: 0.2), value: model.settings.backgroundOpacity)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        .padding(8)
        .overlay(alignment: .leading) { ResizeHandle() }
        .overlay(alignment: .trailing) { ResizeHandle() }
    }

    static let motion: Animation = .spring(response: 0.42, dampingFraction: 0.86)

    private var messages: some View {
        let items = model.notifications.visible
        return VStack(spacing: 8) {
            header("Messages", kinds: [.teams, .mail]) {
                Text("\(items.count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.tint.opacity(0.3), in: .capsule)
                    .contentTransition(.numericText())
                if model.settings.hideFromScreenSharing {
                    Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary)
                        .help("Hidden from screen sharing")
                }
            }
            if items.isEmpty {
                ContentUnavailableView("All caught up", systemImage: "tray")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(items) { n in
                            NotificationCard(item: n, onOpen: { model.open(n) },
                                             onDone: { withAnimation(Self.motion) { model.notifications.markDone(n.id) } },
                                             onSnooze: { o in withAnimation(Self.motion) { model.notifications.snooze(n.id, o) } },
                                             onCreateTodo: { createTodo { model.todos.add(from: n) } },
                                             onDelete: n.kind == .mail ? {
                                                 let r = await model.deleteMail(n)
                                                 return r.message
                                             } : nil)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.92).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 8)
                    .animation(Self.motion, value: items.map(\.id))
                }
                .scrollIndicators(.never)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private var calendar: some View {
        let events = model.events.today
        let upcoming = events.count <= 3 ? model.events.tomorrow : []
        return VStack(spacing: 8) {
            header("Today", kinds: [.calendar]) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if events.isEmpty && upcoming.isEmpty {
                ContentUnavailableView("No more events today", systemImage: "calendar")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        if events.isEmpty {
                            Text("No more events today")
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        ForEach(events) { e in eventCard(e) }
                        if !upcoming.isEmpty {
                            daySeparator("Tomorrow")
                            ForEach(upcoming) { e in eventCard(e) }
                        }
                    }
                    .padding(.vertical, 2)
                    .animation(Self.motion, value: events.map(\.id) + upcoming.map(\.id))
                }
                .scrollIndicators(.never)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func createTodo(_ make: () -> UUID) {
        withAnimation(Self.motion) { openTodo = make() }
    }

    private func eventCard(_ e: CalendarEvent) -> some View {
        EventCard(event: e, onOpen: { model.open(e.webLink) },
                  onJoin: { model.open(e.joinURL) },
                  onDismiss: { withAnimation(Self.motion) { model.events.dismiss(e.id) } })
        .contextMenu {
            Button { createTodo { model.todos.add(from: e) } } label: { Label("Create To Do", systemImage: "checklist") }
        }
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func daySeparator(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase)
            Rectangle().fill(.secondary.opacity(0.35)).frame(height: 1)
        }
        .padding(.horizontal, 8).padding(.top, 6)
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
