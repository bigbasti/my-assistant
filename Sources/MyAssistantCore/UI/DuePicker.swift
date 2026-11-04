import SwiftUI

/// Calendar maths for the due-date dialog (pure, testable).
enum DueDateMath {
    struct Preset: Equatable { let label: String; let date: Date }

    /// Whole weeks covering the month of `date`, starting on the calendar's first weekday.
    static func monthGrid(containing date: Date, calendar: Calendar) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let first = month.start
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: first)!
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let cells = Int((Double(lead + days) / 7).rounded(.up)) * 7
        return (0..<cells).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    static func setting(hour: Int, minute: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func setting(day: Date, keepingTimeOf time: Date, calendar: Calendar) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return setting(hour: t.hour ?? 9, minute: t.minute ?? 0, on: day, calendar: calendar)
    }

    static func presets(now: Date, calendar: Calendar) -> [Preset] {
        var out: [Preset] = []
        let today17 = setting(hour: 17, minute: 0, on: now, calendar: calendar)
        if today17 > now { out.append(Preset(label: "Today 17:00", date: today17)) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        out.append(Preset(label: "Tomorrow 9:00", date: setting(hour: 9, minute: 0, on: tomorrow, calendar: calendar)))
        let monday = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
        out.append(Preset(label: "Next Monday 9:00", date: setting(hour: 9, minute: 0, on: monday, calendar: calendar)))
        out.append(Preset(label: "In a week", date: calendar.date(byAdding: .day, value: 7, to: now)!))
        return out
    }
}

/// Due-date dialog: quick picks, a month calendar, time chips and a precise time field.
struct DuePicker: View {
    let model: AppModel
    let item: TodoItem
    let close: () -> Void
    @State private var date = Date()
    @State private var month = Date()
    /// Focus starts on "Set due" so the time field isn't highlighted and Return confirms.
    @FocusState private var setFocused: Bool
    private let calendar = Calendar.autoupdatingCurrent
    private static let times = [(9, 0), (12, 0), (15, 0), (17, 0)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Due date").font(.headline)
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                    .font(.callout).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            chips(DueDateMath.presets(now: Date(), calendar: calendar).map { ($0.label, $0.date) }) { _, d in
                withAnimation(TodoSection.motion) { date = d; month = d }
            }

            monthView

            HStack(spacing: 6) {
                ForEach(Self.times, id: \.0) { h, m in
                    let on = calendar.component(.hour, from: date) == h && calendar.component(.minute, from: date) == m
                    Button(String(format: "%d:%02d", h, m)) {
                        withAnimation(TodoSection.motion) {
                            date = DueDateMath.setting(hour: h, minute: m, on: date, calendar: calendar)
                        }
                    }
                    .buttonStyle(ChipStyle(selected: on))
                }
                Spacer(minLength: 4)
                DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).fixedSize()
            }

            HStack {
                if item.due != nil {
                    Button("Remove", role: .destructive) {
                        withAnimation(TodoSection.motion) { model.todos.setDue(item.id, nil) }
                        close()
                    }
                    .buttonStyle(.glass)
                }
                Spacer()
                Button("Set due") {
                    withAnimation(TodoSection.motion) { model.todos.setDue(item.id, date) }
                    close()
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .focused($setFocused)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            date = item.due ?? DueDateMath.presets(now: Date(), calendar: calendar).first?.date ?? Date()
            month = date
            DispatchQueue.main.async { setFocused = true }
        }
    }

    private var monthView: some View {
        let days = DueDateMath.monthGrid(containing: month, calendar: calendar)
        let symbols = Array(calendar.veryShortStandaloneWeekdaySymbols.rotated(by: calendar.firstWeekday - 1))
        return VStack(spacing: 6) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.subheadline.bold())
                    .contentTransition(.opacity)
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2.bold()).foregroundStyle(.tertiary)
                }
                ForEach(days, id: \.self) { day in dayCell(day) }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let selected = calendar.isDate(day, inSameDayAs: date)
        let today = calendar.isDateInToday(day)
        let past = day < calendar.startOfDay(for: Date())
        return Button {
            withAnimation(TodoSection.motion) {
                date = DueDateMath.setting(day: day, keepingTimeOf: date, calendar: calendar)
            }
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.callout.monospacedDigit().weight(selected ? .bold : .regular))
                .frame(width: 30, height: 30)
                .foregroundStyle(selected ? Color.white : inMonth ? Color.primary : Color.secondary.opacity(0.5))
                .background {
                    if selected { Circle().fill(Color.accentColor) }
                    else if today { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(past)
        .opacity(past ? 0.35 : 1)
    }

    private func shiftMonth(_ by: Int) {
        withAnimation(TodoSection.motion) { month = calendar.date(byAdding: .month, value: by, to: month) ?? month }
    }

    private func chips(_ items: [(String, Date)], action: @escaping (String, Date) -> Void) -> some View {
        FlowRow(spacing: 6) {
            ForEach(items, id: \.0) { label, d in
                Button(label) { action(label, d) }
                    .buttonStyle(ChipStyle(selected: abs(d.timeIntervalSince(date)) < 60))
            }
        }
    }
}

/// Small capsule button used for quick picks.
struct ChipStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.18), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Wraps its children onto new lines when they don't fit.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

private extension Array {
    func rotated(by n: Int) -> [Element] {
        guard !isEmpty else { return self }
        let k = ((n % count) + count) % count
        return Array(self[k...] + self[..<k])
    }
}
