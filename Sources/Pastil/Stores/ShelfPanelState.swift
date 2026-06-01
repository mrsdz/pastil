import Foundation

final class ShelfPanelState: ObservableObject {
    @Published var selectedItemID: UUID?
    /// Bumped each time the shelf is summoned so the search field can re-focus
    /// and select its contents.
    @Published var searchFocusTrigger = 0
}
