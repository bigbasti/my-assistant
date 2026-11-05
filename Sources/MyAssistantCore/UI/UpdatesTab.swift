import SwiftUI

struct UpdatesTab: View {
    let c: SettingsController

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version") {
                    Text(c.updater.map { "\($0.currentVersion)" } ?? "–").monospacedDigit()
                }
                Toggle("Check for updates automatically",
                       isOn: Binding(get: { c.model.settings.autoCheckUpdates }, set: { c.setAutoCheckUpdates($0) }))
                if let last = c.model.settings.lastUpdateCheck {
                    LabeledContent("Last checked") {
                        Text(last.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Updates come from the releases on github.com/\(Updater.repo).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section { status }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var status: some View {
        switch c.updater?.state ?? .idle {
        case .idle:
            checkButton
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking GitHub…") }
        case .upToDate:
            VStack(alignment: .leading, spacing: 8) {
                Label("My Assistant is up to date.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                checkButton
            }
        case .available(let release):
            VStack(alignment: .leading, spacing: 10) {
                Label("Version \(release.version) is available.", systemImage: "arrow.down.circle.fill")
                    .font(.headline).foregroundStyle(.blue)
                ScrollView {
                    Text(LocalizedStringKey(Self.changes(in: release.notes)))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                HStack {
                    if let page = release.pageURL { Link("Release page", destination: page) }
                    Spacer()
                    Button("Download & Install") { Task { await c.updater?.install(release) } }
                        .buttonStyle(.glassProminent)
                }
                Text("My Assistant quits, updates itself and starts again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading…")
                ProgressView(value: progress)
            }
        case .installing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Installing — the app restarts in a moment…") }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                checkButton
            }
        }
    }

    private var checkButton: some View {
        Button("Check for Updates") { Task { await c.updater?.check() } }
    }

    /// Only the "Changes" part of the release notes (install instructions are irrelevant here).
    static func changes(in notes: String) -> String {
        guard let r = notes.range(of: "## Changes") else { return notes }
        let rest = notes[r.upperBound...]
        let end = rest.range(of: "SHA-256:")?.lowerBound ?? rest.endIndex
        return rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
