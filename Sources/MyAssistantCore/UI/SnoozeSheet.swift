import SwiftUI

public struct SnoozeSheet: View {
    let firstSurfacedAt: Date
    let onPick: (SnoozeOption) -> Void
    @State private var custom = false
    @State private var date: Date

    public init(firstSurfacedAt: Date, onPick: @escaping (SnoozeOption) -> Void) {
        self.firstSurfacedAt = firstSurfacedAt
        self.onPick = onPick
        _date = State(initialValue: SnoozeOption.tomorrow.resurfaceDate(now: Date(), firstSurfacedAt: firstSurfacedAt, calendar: .current))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SnoozeOption.presets, id: \.self) { o in
                Button(o.label) { onPick(o) }
                    .buttonStyle(.glass).frame(maxWidth: .infinity)
            }
            Button("Custom…") { withAnimation { custom.toggle() } }
                .buttonStyle(.glass).frame(maxWidth: .infinity)
            if custom {
                DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date])
                    .datePickerStyle(.graphical).labelsHidden()
                    .frame(maxWidth: .infinity)
                HStack {
                    Text("Time").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.stepperField).labelsHidden()
                }
                Button("Snooze") { onPick(.custom(date)) }
                    .buttonStyle(.glassProminent).frame(maxWidth: .infinity)
                    .disabled(date <= Date())
            }
        }
        .padding(16)
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }
}
