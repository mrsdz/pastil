import AppKit
import ApplicationServices
import QuartzCore
import SwiftUI

final class ShelfPanelController {
    private let store: ClipboardStore
    private let state: ShelfPanelState
    private var panel: PastilShelfPanel?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private weak var previousApplication: NSRunningApplication?

    init(store: ClipboardStore, state: ShelfPanelState) {
        self.store = store
        self.state = state
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        store.startMonitoring()

        let panel = existingOrCreatePanel()
        position(panel)
        panel.alphaValue = 0
        // Become key for keyboard input WITHOUT activating the app — this keeps the
        // app you copied from frontmost, so the synthetic ⌘V (and its caret) land there.
        panel.makeKeyAndOrderFront(nil)
        installEventMonitor()
        state.searchFocusTrigger += 1

        let finalFrame = panel.frame
        panel.setFrame(finalFrame.offsetBy(dx: 0, dy: -36), display: false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeEventMonitor()
        let finalFrame = panel.frame.offsetBy(dx: 0, dy: -28)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    func copySelected() {
        guard let item = selectedItem else { return }
        store.copy(item)
        hide()
    }

    func pasteSelected(asPlainText: Bool = false) {
        guard let item = selectedItem else { return }
        paste(item, asPlainText: asPlainText)
    }

    func paste(_ item: ClipboardItem, asPlainText: Bool = false) {
        if asPlainText {
            store.copyPlainText(item)
        } else {
            store.copy(item)
        }

        // Dismiss immediately (no close animation) and hand focus back to the source app
        // BEFORE synthesizing the paste — order matters or ⌘V lands nowhere.
        removeEventMonitor()
        panel?.orderOut(nil)
        previousApplication?.activate()

        // Auto-paste needs Accessibility trust. Check silently (no prompt) — the clip is
        // already on the clipboard, so the user can ⌘V manually if it isn't granted.
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.sendCommandV()
        }
    }

    func selectScope(at index: Int) {
        var scopes: [LibraryScope] = [.all, .favorites]
        scopes += store.pinboards.prefix(4).map { .pinboard($0.id) }
        guard scopes.indices.contains(index) else { return }
        store.selectedScope = scopes[index]
    }

    func openSettings() {
        hide()
        let contentSize = NSSize(width: 460, height: 540)
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(store)
                    .frame(width: contentSize.width, height: contentSize.height)
            )
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.title = "Pastil Settings"
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.setContentSize(contentSize)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func moveSelection(_ direction: Int) {
        let items = store.visibleItems
        guard !items.isEmpty else {
            state.selectedItemID = nil
            return
        }

        guard let selectedID = state.selectedItemID,
              let index = items.firstIndex(where: { $0.id == selectedID }) else {
            state.selectedItemID = items.first?.id
            return
        }

        let nextIndex = min(max(index + direction, 0), items.count - 1)
        state.selectedItemID = items[nextIndex].id
    }

    func deleteSelected() {
        let items = store.visibleItems
        guard let id = state.selectedItemID,
              let index = items.firstIndex(where: { $0.id == id }),
              let item = store.item(for: id) else { return }

        let nextID: UUID? = index + 1 < items.count
            ? items[index + 1].id
            : (index - 1 >= 0 ? items[index - 1].id : nil)
        store.delete(item)
        state.selectedItemID = nextID
    }

    private var selectedItem: ClipboardItem? {
        store.item(for: state.selectedItemID)
    }

    private func existingOrCreatePanel() -> PastilShelfPanel {
        if let panel {
            return panel
        }

        let content = BottomShelfPanelView(
            onPaste: { [weak self] item, asPlainText in self?.paste(item, asPlainText: asPlainText) },
            onClose: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        .environmentObject(store)
        .environmentObject(state)

        let hostingController = NSHostingController(rootView: content)
        let panel = PastilShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        // Sit just above the Dock so the shelf can anchor to the very bottom edge.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        // Anchor to the full screen frame (not visibleFrame) so the shelf starts at
        // the very bottom edge and spans the entire width, covering the Dock like Paste.
        let frame = screen.frame
        // Fixed height that hugs the card row — avoids the large empty gap below cards.
        let height: CGFloat = 264
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: height), display: false)
    }

    private func installEventMonitor() {
        removeEventMonitor()

        // Clicking anywhere outside the shelf (another app, the desktop, the Dock)
        // dismisses it. Global monitors only fire for events targeting other apps,
        // so clicks inside the panel / its popovers are unaffected.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }

        // Card keyboard shortcuts. Guarded so they only fire while the shelf itself is
        // the key window — when the new-category popover or Settings is key, these pass
        // through and those fields behave normally.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel?.isKeyWindow == true else { return event }

            if event.modifierFlags.contains(.command) {
                if event.keyCode == 8 { // ⌘C — copy the selected clip again
                    copySelected()
                    return nil
                }
                if let index = Self.scopeIndex(forKeyCode: event.keyCode) { // ⌘1…⌘9 — switch category
                    selectScope(at: index)
                    return nil
                }
            }

            switch event.keyCode {
            case 53: // escape
                hide()
                return nil
            case 36, 76: // return / enter (⇧ pastes as plain text)
                pasteSelected(asPlainText: event.modifierFlags.contains(.shift))
                return nil
            case 123: // left arrow
                moveSelection(-1)
                return nil
            case 124: // right arrow
                moveSelection(1)
                return nil
            case 51, 117: // delete / forward delete
                // Only delete a card when there's no search query to edit.
                guard store.searchText.isEmpty else { return event }
                deleteSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removeEventMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// Maps a number-row key code (1…9) to a zero-based category index.
    private static func scopeIndex(forKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 0 // 1
        case 19: return 1 // 2
        case 20: return 2 // 3
        case 21: return 3 // 4
        case 23: return 4 // 5
        case 22: return 5 // 6
        case 26: return 6 // 7
        case 28: return 7 // 8
        case 25: return 8 // 9
        default: return nil
        }
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

final class PastilShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
