import AppKit
import SwiftUI

@main
struct PastilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppServices.store

    var body: some Scene {
        // No menu bar item: the shelf is summoned with the global ⌘⇧V hotkey
        // (registered in AppServices). The app runs as a background accessory.
        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--render-debug") {
            DebugSupport.run()
            DebugSupport.flush()
            exit(0)
        }
        if CommandLine.arguments.contains("--test-paste") {
            DebugSupport.testPaste()
            DebugSupport.flush()
            exit(0)
        }
        if CommandLine.arguments.contains("--test-textedit") {
            DebugSupport.testTextEdit()
            DebugSupport.flush()
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)
        AppServices.start()
    }
}

extension Notification.Name {
    static let copySelectedClip = Notification.Name("Pastil.copySelectedClip")
    static let pasteSelectedClip = Notification.Name("Pastil.pasteSelectedClip")
}
