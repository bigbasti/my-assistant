import SwiftUI

/// The "To Dos" section of the panel.
struct TodoSection: View {
    let model: AppModel
    @Binding var expanded: Bool
    @Binding var openID: UUID?
    /// Height the section needs for its current rows (reported so the panel can size it).
    @Binding var contentHeight: CGFloat

    static let motion: Animation = .spring(response: 0.42, dampingFraction: 0.86)

    var body: some View {
        let store = model.todos
        let items = expanded ? store.all : store.visible
        VStack(spacing: 8) {
            header(count: store.visible.count)
            if items.isEmpty {
                Text(expanded ? "No to-dos yet. Use + or right-click a card." : "Nothing to do 🎉")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .transition(.opacity)
                    .onAppear { contentHeight = 32 }
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { t in
                            TodoRow(model: model, item: t, showsTrash: expanded, isOpen: openID == t.id) {
                                withAnimation(Self.motion) { openID = openID == t.id ? nil : t.id }
                            }
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .scale(scale: 0.92).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .animation(Self.motion, value: items.map(\.id))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollIndicators(.never)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Text("To Dos").font(.title3.bold())
            Text("\(count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                .background(.tint.opacity(0.3), in: .capsule)
                .contentTransition(.numericText())
            Spacer()
            Button {
                withAnimation(Self.motion) { expanded.toggle() }
            } label: {
                Label(expanded ? "Show less" : "Show more",
                      systemImage: expanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .labelStyle(.iconOnly)
            }
            .help(expanded ? "Show less" : "Show all to-dos")
            Button {
                withAnimation(Self.motion) {
                    let id = model.todos.add(title: "New to-do")
                    openID = id
                }
            } label: { Image(systemName: "plus.circle.fill") }
            .help("New to-do")
        }
        .buttonStyle(.plain).font(.title3)
        .padding(.horizontal, 8)
    }
}

struct TodoRow: View {
    let model: AppModel
    let item: TodoItem
    let showsTrash: Bool
    let isOpen: Bool
    let toggleOpen: () -> Void

    private var due: TodoItem.DueState { model.todos.dueState(item) }

    private var accent: Color {
        switch due {
        case .overdue: .red
        case .today: .orange
        default: .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(TodoSection.motion) { model.todos.toggleDone(item.id) }
                } label: {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.done ? Color.green : accent)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain).help(item.done ? "Mark as open" : "Mark as done")

                Text(item.title)
                    .lineLimit(1)
                    .strikethrough(item.done, color: .secondary)
                    .foregroundStyle(item.done ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleOpen)

                if model.todos.isSnoozed(item), let until = item.snoozedUntil {
                    Label(until.formatted(.dateTime.weekday(.abbreviated).hour().minute()), systemImage: "moon.zzz")
                        .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
                dueBadge
                if showsTrash {
                    Button { withAnimation(TodoSection.motion) { model.todos.delete(item.id) } } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete")
                }
            }
            if isOpen {
                TodoDetail(model: model, item: item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .glassEffect(.regular.tint(accent.opacity(due == .overdue || due == .today ? 0.18 : 0.06)),
                     in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            if due == .overdue || due == .today, !item.done {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accent.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(TodoSection.motion, value: isOpen)
    }

    @ViewBuilder private var dueBadge: some View {
        if let d = item.due, !item.done {
            Text(due == .today || due == .overdue ? d.formatted(date: .omitted, time: .shortened)
                                                   : d.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption.bold().monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(due == .upcoming ? Color.secondary.opacity(0.25) : accent, in: .capsule)
                .foregroundStyle(due == .upcoming ? Color.primary : Color.white)
        }
    }
}

/// Opened row: title editing, note, due date, reschedule, original item.
struct TodoDetail: View {
    let model: AppModel
    let item: TodoItem
    @State private var editingNote = false
    @State private var title = ""
    @State private var showDue = false
    @State private var showReschedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.todos.rename(item.id, title) }
                .onChange(of: title) { model.todos.rename(item.id, title) }

            if editingNote {
                RichNoteEditor(text: Binding(get: { NoteFormatting.withDefaultColor(item.note) },
                                             set: { model.todos.setNote(item.id, NoteFormatting.withoutDefaultColor($0)) })) {
                    withAnimation(TodoSection.motion) { editingNote = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                Group {
                    if item.note.characters.isEmpty {
                        Text("Add a note…").foregroundStyle(.secondary)
                    } else {
                        Text(item.note)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(TodoSection.motion) { editingNote = true } }
                .help("Click to edit")
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                Button { showDue = true } label: {
                    Label(item.due.map { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) } ?? "Due date",
                          systemImage: "calendar.badge.clock")
                }
                .popover(isPresented: $showDue) { DuePicker(model: model, item: item) { showDue = false } }

                Button { showReschedule = true } label: { Label("Reschedule", systemImage: "clock.arrow.circlepath") }
                    .popover(isPresented: $showReschedule) {
                        SnoozeSheet(firstSurfacedAt: Date()) { o in
                            showReschedule = false
                            withAnimation(TodoSection.motion) { model.todos.reschedule(item.id, o) }
                        }
                    }
                if model.todos.isSnoozed(item) {
                    Button { model.todos.clearReschedule(item.id) } label: { Label("Show now", systemImage: "sun.max") }
                }
                Spacer()
                if let ref = item.reference {
                    Button { model.open(ref) } label: {
                        Label("Open \(ref.label)", systemImage: ref.kind.icon).lineLimit(1)
                    }
                    .help("Open the original \(ref.kind == .calendar ? "meeting" : ref.kind == .mail ? "mail" : "message")")
                }
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            .lineLimit(1).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { title = item.title }
    }
}
