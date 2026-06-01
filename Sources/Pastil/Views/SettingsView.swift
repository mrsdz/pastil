import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ClipboardStore
    @State private var newExcludedBundleID = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch Pastil at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                LabeledContent("Show shelf") {
                    Text("⌘⇧V")
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }

            Section("History") {
                Stepper(value: $store.maximumHistoryCount, in: 50...5000, step: 50) {
                    Text("Keep \(store.maximumHistoryCount) clips")
                }
                Toggle("Capture images", isOn: $store.captureImages)
                Button("Clear History", role: .destructive) {
                    store.clearUnpinned()
                }
                .help("Removes everything except favorites and clips filed in a category.")
            }

            Section("Ignored Apps") {
                Text("Pastil will not store clips copied from these bundle identifiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(store.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button {
                            store.excludedBundleIDs.remove(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("com.example.SecretApp", text: $newExcludedBundleID)
                        .onSubmit(addExcludedApp)
                    Button("Add", action: addExcludedApp)
                        .disabled(newExcludedBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func addExcludedApp() {
        let trimmed = newExcludedBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.excludedBundleIDs.insert(trimmed)
        newExcludedBundleID = ""
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Pastil could not update login item: \(error.localizedDescription)")
            // Reflect the real state if the system rejected the change.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
