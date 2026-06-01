import AppKit
import ApplicationServices
import SwiftUI

struct BottomShelfPanelView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var state: ShelfPanelState

    @State private var showingNewCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryColor = "sky"
    @State private var editingPinboardID: UUID?
    @State private var editName = ""
    @State private var editColor = "sky"
    @State private var dropTarget: LibraryScope?

    private static let leadingAnchorID = "pastil.leadingEdge"

    /// Pastes the given clip; the Bool requests plain-text paste.
    let onPaste: (ClipboardItem, Bool) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.visibleItems.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                clipStrip
            }
        }
        .background(trayBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 1)
        }
        .onChange(of: store.visibleItems.map(\.id)) { _, ids in
            guard !ids.contains(where: { $0 == state.selectedItemID }) else { return }
            state.selectedItemID = ids.first
        }
    }

    private var clipStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    // Leading margin sentinel — scrolled to instead of the first card so the
                    // newest card keeps its left margin instead of butting against the edge.
                    Color.clear
                        .frame(width: 14, height: 1)
                        .id(Self.leadingAnchorID)

                    ForEach(store.visibleItems) { item in
                        ClipCard(item: item, isSelected: state.selectedItemID == item.id)
                            .equatable()
                            .id(item.id)
                            .modifier(CardDraggable(item: item))
                            .contextMenu { cardMenu(for: item) }
                            .onTapGesture(count: 2) {
                                state.selectedItemID = item.id
                                onPaste(item, false)
                            }
                            .simultaneousGesture(
                                TapGesture().onEnded { state.selectedItemID = item.id }
                            )
                    }
                }
                .padding(.trailing, 28)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.never)
            .onChange(of: state.selectedItemID) { _, id in
                guard let id else { return }
                withAnimation(.smooth(duration: 0.18)) {
                    if id == store.visibleItems.first?.id {
                        proxy.scrollTo(Self.leadingAnchorID, anchor: .leading)
                    } else {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: state.searchFocusTrigger) { _, _ in
                jumpToLatest(proxy)
            }
            .onAppear {
                jumpToLatest(proxy)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                FocusableTextField(
                    text: $store.searchText,
                    placeholder: "Search",
                    focusTrigger: state.searchFocusTrigger
                )
                .frame(maxWidth: .infinity)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(width: 240, height: 32)
            .liquidGlass(in: Capsule())

            shelfChip(title: "Clipboard", color: .pastilSky, scope: .all)
            shelfChip(title: "Favorites", color: .pastilCoral, scope: .favorites)

            ForEach(store.pinboards.prefix(4)) { pinboard in
                shelfChip(
                    title: pinboard.name,
                    color: Color.pinboard(pinboard.colorName),
                    scope: .pinboard(pinboard.id)
                )
                .contextMenu {
                    Button {
                        beginEditing(pinboard)
                    } label: {
                        Label("Edit Category…", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        store.removePinboard(pinboard)
                    } label: {
                        Label("Delete Category", systemImage: "trash")
                    }
                }
                .popover(isPresented: editingBinding(for: pinboard), arrowEdge: .bottom) {
                    categoryForm(title: "Edit Category", name: $editName, colorName: $editColor) {
                        store.updatePinboard(pinboard.id, name: editName, colorName: editColor)
                        editingPinboardID = nil
                    }
                }
            }

            newCategoryButton

            Spacer()

            Text("Return paste")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            optionsMenu

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .liquidGlass(in: Circle())
            .help("Close")
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var newCategoryButton: some View {
        Button {
            showingNewCategory.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(in: Circle())
        .help("New category")
        .popover(isPresented: $showingNewCategory, arrowEdge: .bottom) {
            categoryForm(title: "New Category", name: $newCategoryName, colorName: $newCategoryColor) {
                store.addPinboard(named: newCategoryName, colorName: newCategoryColor)
                newCategoryName = ""
                newCategoryColor = "sky"
                showingNewCategory = false
            }
        }
    }

    private func categoryForm(
        title: String,
        name: Binding<String>,
        colorName: Binding<String>,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("Name", text: name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(action)
            HStack(spacing: 8) {
                ForEach(Color.pinboardColorNames, id: \.self) { swatch in
                    Circle()
                        .fill(Color.pinboard(swatch))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().strokeBorder(.primary.opacity(colorName.wrappedValue == swatch ? 0.9 : 0), lineWidth: 2)
                        }
                        .contentShape(Circle())
                        .onTapGesture { colorName.wrappedValue = swatch }
                }
            }
            HStack {
                Spacer()
                Button("Save", action: action)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 268)
    }

    private func editingBinding(for pinboard: Pinboard) -> Binding<Bool> {
        Binding(
            get: { editingPinboardID == pinboard.id },
            set: { if !$0 { editingPinboardID = nil } }
        )
    }

    private func beginEditing(_ pinboard: Pinboard) {
        editName = pinboard.name
        editColor = pinboard.colorName
        editingPinboardID = pinboard.id
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                onOpenSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            if !AXIsProcessTrusted() {
                Button {
                    requestAccessibility()
                } label: {
                    Label("Enable Auto-Paste…", systemImage: "hand.raised")
                }
            }
            Button {
                store.clearUnpinned()
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Pastil", systemImage: "power")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .liquidGlass(in: Circle())
        .help("More options")
    }

    private func shelfChip(title: String, color: Color, scope: LibraryScope) -> some View {
        let isSelected = store.selectedScope == scope
        let isTargeted = dropTarget == scope
        return Button {
            store.selectedScope = scope
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .liquidGlass(in: Capsule())
            .overlay {
                if isSelected || isTargeted {
                    Capsule().strokeBorder(color.opacity(isTargeted ? 1 : 0.65), lineWidth: isTargeted ? 2.5 : 1.5)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(isTargeted ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { ids, _ in
            applyDrop(ids, to: scope)
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTarget = scope
            } else if dropTarget == scope {
                dropTarget = nil
            }
        }
        .animation(.smooth(duration: 0.12), value: isTargeted)
    }

    private var trayBackground: some View {
        ZStack {
            // Native behind-window blur of the desktop. Cheaper than a full-width
            // `.glassEffect` layer (which was re-rasterizing the whole tray); the glass
            // chrome (search / chips / buttons) carries the Liquid Glass character.
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
            // Subtle top sheen for the glass edge highlight.
            LinearGradient(
                colors: [.white.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(store.searchText.isEmpty ? "Copy something" : "No matches")
                .font(.headline)
            Text(store.searchText.isEmpty ? "Your clipboard history appears here." : "Try a different search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func applyDrop(_ contents: [String], to scope: LibraryScope) {
        for content in contents {
            // Cards drag their text content (so they also paste into other apps); match
            // it back to the most-recent clip to file it under the dropped category.
            guard let item = store.items.first(where: { $0.content == content }) else { continue }
            switch scope {
            case .favorites:
                store.updateItem(id: item.id) { $0.isFavorite = true }
            case .pinboard(let pinboardID):
                store.updateItem(id: item.id) { $0.pinboardIDs.insert(pinboardID) }
            default:
                break
            }
        }
    }

    private func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    @ViewBuilder
    private func cardMenu(for item: ClipboardItem) -> some View {
        Button {
            onPaste(item, false)
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        if item.kind == .text || item.kind == .code || item.kind == .link {
            Button {
                onPaste(item, true)
            } label: {
                Label("Paste as Plain Text", systemImage: "textformat")
            }
        }
        Menu {
            Button {
                store.updateItem(id: item.id) { $0.isFavorite = true }
            } label: {
                Label("Favorites", systemImage: "star")
            }
            ForEach(store.pinboards) { pinboard in
                Button {
                    store.updateItem(id: item.id) { $0.pinboardIDs.insert(pinboard.id) }
                } label: {
                    Text(pinboard.name)
                }
            }
        } label: {
            Label("Add to Category", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) {
            deleteItem(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteItem(_ item: ClipboardItem) {
        let items = store.visibleItems
        if state.selectedItemID == item.id, let index = items.firstIndex(where: { $0.id == item.id }) {
            state.selectedItemID = index + 1 < items.count
                ? items[index + 1].id
                : (index - 1 >= 0 ? items[index - 1].id : nil)
        }
        store.delete(item)
    }

    private func jumpToLatest(_ proxy: ScrollViewProxy) {
        state.selectedItemID = store.visibleItems.first?.id
        proxy.scrollTo(Self.leadingAnchorID, anchor: .leading)
    }
}

private struct ClipCard: View, Equatable {
    @EnvironmentObject private var store: ClipboardStore
    let item: ClipboardItem
    let isSelected: Bool

    // Skip re-rendering cards whose displayed content didn't change. Deliberately
    // ignores the heavy image/icon Data blobs (keyed by id, they never change).
    static func == (lhs: ClipCard, rhs: ClipCard) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.item.id == rhs.item.id
            && lhs.item.isFavorite == rhs.item.isFavorite
            && lhs.item.createdAt == rhs.item.createdAt
            && lhs.item.content == rhs.item.content
            && lhs.item.sourceAppName == rhs.item.sourceAppName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            preview
            footer
        }
        .padding(12)
        .frame(width: 184, height: 176)
        .background(cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2.5 : 1
                )
        }
        .shadow(color: .black.opacity(isSelected ? 0.22 : 0.12), radius: isSelected ? 14 : 7, y: isSelected ? 8 : 4)
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.smooth(duration: 0.16), value: isSelected)
    }

    private var header: some View {
        HStack(spacing: 7) {
            appIcon
            Text(item.sourceAppName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                store.toggleFavorite(item)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let nsImage = DecodedImageCache.shared.image(forKey: "\(item.id)-icon", data: item.appIconData) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            imagePreview
        case .color:
            colorPreview
        case .code:
            Text(item.content)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .link:
            Text(item.content)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tint)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .file:
            filePreview
        case .text:
            Text(item.content)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var imagePreview: some View {
        Group {
            if let nsImage = DecodedImageCache.shared.thumbnail(forKey: "\(item.id)-image", data: item.imageData, maxPixel: 360) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                fallbackPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var colorPreview: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(hex: item.content) ?? .accentColor)
            .overlay(alignment: .bottomLeading) {
                Text(item.content.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fallbackPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.headline)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            Text(item.kind.label)
                .font(.caption2.weight(.semibold))
            Spacer()
            Text(RelativeDates.string(from: item.createdAt))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    private var cardSurface: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

/// Makes a card draggable with its real content, so dragging it onto another app pastes
/// the clip (text → text, image → image, file → file). Text-like clips carry their string,
/// which also lets them be dropped onto a category chip.
private struct CardDraggable: ViewModifier {
    let item: ClipboardItem

    @ViewBuilder
    func body(content: Content) -> some View {
        switch item.kind {
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                content.draggable(Image(nsImage: nsImage))
            } else {
                content.draggable(item.content)
            }
        case .file:
            content.draggable(URL(fileURLWithPath: item.content))
        default:
            content.draggable(item.content)
        }
    }
}
