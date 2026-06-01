import AppKit
import ApplicationServices
import SwiftUI

/// Headless self-check: prints the Accessibility trust state and snapshots the real
/// AppKit window hierarchy (via `cacheDisplay`, no screen-recording permission needed)
/// so the views can be inspected. Invoked with `Pastil --render-debug`.
enum DebugSupport {
    @MainActor
    static func run() {
        NSApp.setActivationPolicy(.regular)
        log("ACCESSIBILITY_TRUSTED=\(AXIsProcessTrusted())")

        let store = AppServices.store
        let state = AppServices.shelfState
        log("CLIP_COUNT=\(store.items.count)")

        snapshot(
            SettingsView().environmentObject(store),
            size: CGSize(width: 460, height: 540),
            to: "/tmp/pastil_settings.png"
        )

        snapshot(
            BottomShelfPanelView(onPaste: { _, _ in }, onClose: {}, onOpenSettings: {})
                .environmentObject(store)
                .environmentObject(state),
            size: CGSize(width: 1280, height: 264),
            to: "/tmp/pastil_shelf.png"
        )
    }

    @MainActor
    static func snapshot<V: View>(_ view: V, size: CGSize, to path: String) {
        let hosting = NSHostingController(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        let window = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.setContentSize(size)
        window.orderFront(nil)

        // Let SwiftUI lay out and draw the hosted hierarchy before capturing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let contentView = window.contentView,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            log("SNAPSHOT_FAILED \(path)")
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            log("SNAPSHOT \(path) (\(png.count) bytes)")
        }
        window.orderOut(nil)
    }

    /// Probes which paste mechanism actually works on this system: copies a token,
    /// focuses our own text view, and tries each delivery method in turn.
    @MainActor
    static func testPaste() {
        NSApp.setActivationPolicy(.regular)
        log("ACCESSIBILITY_TRUSTED=\(AXIsProcessTrusted())")

        let token = "PASTIL_PASTE_TEST"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        let window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        log("IS_KEY=\(window.isKeyWindow) FR_IS_TEXT=\(window.firstResponder is NSText)")

        let pid = ProcessInfo.processInfo.processIdentifier

        probe("DIRECT_PASTE", textView) { textView.paste(nil) }
        probe("HID_TAP", textView) { postCmdV(.cghidEventTap, pid: nil) }
        probe("SESSION_TAP", textView) { postCmdV(.cgSessionEventTap, pid: nil) }
        probe("POST_TO_PID", textView) { postCmdV(nil, pid: pid) }
    }

    @MainActor
    private static func probe(_ name: String, _ textView: NSTextView, _ action: () -> Void) {
        textView.string = ""
        action()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        log("\(name)=[\(textView.string)]")
    }

    /// End-to-end paste test against a real app: opens a temp file in TextEdit, copies a
    /// token, activates TextEdit, fires the synthetic ⌘V, then reads TextEdit's focused
    /// text back via the Accessibility API to confirm the paste actually landed.
    @MainActor
    static func testTextEdit() {
        NSApp.setActivationPolicy(.accessory)
        log("ACCESSIBILITY_TRUSTED=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else { log("ABORT_NOT_TRUSTED"); return }

        let token = "PASTILPASTE\(abs(UUID().hashValue % 1_000_000))"
        let target = URL(fileURLWithPath: "/tmp/pastil_paste_target.txt")
        try? Data().write(to: target)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        var tePid: pid_t = 0
        var opened = false
        NSWorkspace.shared.open(
            [target],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
            configuration: config
        ) { app, _ in
            tePid = app?.processIdentifier ?? 0
            opened = true
        }
        while !opened { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))

        NSRunningApplication(processIdentifier: tePid)?.activate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        log("TEXTEDIT_PID=\(tePid)")

        postCmdV(.cghidEventTap, pid: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))

        let content = readFocusedText(pid: tePid)
        log("TEXTEDIT_CONTENT=[\(content ?? "nil")]")
        log("PASTE_OK=\(content?.contains(token) == true)")
    }

    private static func readFocusedText(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        let axElement = element as! AXUIElement
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value) == .success {
            return value as? String
        }
        return nil
    }

    private static func postCmdV(_ tap: CGEventTapLocation?, pid: pid_t?) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        if let pid {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        } else if let tap {
            keyDown.post(tap: tap)
            keyUp.post(tap: tap)
        }
    }

    private static var output: [String] = []

    private static func log(_ message: String) {
        output.append(message)
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }

    static func flush() {
        try? output.joined(separator: "\n").write(toFile: "/tmp/pastil_debug.log", atomically: true, encoding: .utf8)
    }
}
