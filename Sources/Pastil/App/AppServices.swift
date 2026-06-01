import Foundation

enum AppServices {
    static let store = ClipboardStore()
    static let shelfState = ShelfPanelState()
    static let shelfPanel = ShelfPanelController(store: store, state: shelfState)
    static let hotKey = HotKeyController {
        AppServices.shelfPanel.toggle()
    }

    static func start() {
        store.startMonitoring()
        hotKey.register()
    }
}
