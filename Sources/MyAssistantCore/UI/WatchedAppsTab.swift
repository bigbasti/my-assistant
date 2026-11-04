import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WatchedAppsTab: View {
    let c: SettingsController
    @State private var showPicker = false

    var body: some View {
        Form {
            Section {
                Toggle("Restart watched apps when they quit",
                       isOn: Binding(get: { c.model.settings.keepAppsRunning }, set: { c.setKeepAppsRunning($0) }))
            } footer: {
                Text("Missing apps are restarted in the background without taking focus. To really quit a watched app, switch it off here first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Watched") {
                if c.model.settings.watched.isEmpty {
                    Text("No apps watched yet.").foregroundStyle(.secondary)
                }
                ForEach(c.model.settings.watched) { item in
                    row(item)
                }
                HStack {
                    Button("Choose app…") { chooseApp() }
                    Button("Pick running…") { showPicker = true }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showPicker) {
            RunningPicker { item in c.addWatched(item); showPicker = false } cancel: { showPicker = false }
        }
    }

    private func row(_ item: WatchedItem) -> some View {
        HStack(spacing: 10) {
            icon(item).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                statusText(c.keeper?.status[item.id], enabled: item.enabled)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { item.enabled }, set: { c.setWatched(item.id, enabled: $0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button { c.removeWatched(item.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help("Stop watching")
        }
    }

    @ViewBuilder private func icon(_ item: WatchedItem) -> some View {
        switch item.target {
        case .app(_, let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        case .process:
            Image(systemName: "terminal").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func statusText(_ s: KeeperStatus?, enabled: Bool) -> some View {
        Group {
            switch s {
            case .running: Text("Running").foregroundStyle(.green)
            case .restarted(let d):
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("Restarted \(relativeTime(from: d, now: ctx.date))").foregroundStyle(.blue)
                }
            case .paused: Text("Paused: keeps quitting right after restart. Switch off and on to retry.").foregroundStyle(.orange)
            case .failed(let m): Text("Couldn't start: \(m)").foregroundStyle(.red)
            case .off, .none: Text(enabled ? "Waiting…" : "Off").foregroundStyle(.secondary)
            }
        }
        .font(.caption).lineLimit(2)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { c.addWatched(.app(at: $0)) }
    }
}

private struct RunningPicker: View {
    let pick: (WatchedItem) -> Void
    let cancel: () -> Void
    @State private var allProcesses = false
    @State private var query = ""
    @State private var entries: [ProcessList.Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a running app").font(.headline)
            HStack {
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Show all processes", isOn: $allProcesses).toggleStyle(.checkbox)
            }
            List(filtered) { e in
                Button { pick(e.item) } label: {
                    HStack {
                        if case .app(_, let path) = e.item.target {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "terminal").frame(width: 18, height: 18)
                        }
                        Text(e.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(e.pid)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 280)
            HStack { Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction) }
        }
        .padding(16)
        .frame(width: 460, height: 420)
        .onAppear(perform: reload)
        .onChange(of: allProcesses) { reload() }
    }

    private var filtered: [ProcessList.Entry] {
        query.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func reload() {
        entries = ProcessList.runningApps() + (allProcesses ? ProcessList.userProcesses() : [])
    }
}
