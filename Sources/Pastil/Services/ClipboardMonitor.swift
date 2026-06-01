import AppKit
import Foundation
import UniformTypeIdentifiers

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var timer: Timer?
    private var isWritingProgrammatically = false

    init() {
        changeCount = pasteboard.changeCount
    }

    func start(onCapture: @escaping (ClipboardItem) -> Void) {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.poll(onCapture: onCapture)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copy(_ item: ClipboardItem) {
        isWritingProgrammatically = true
        pasteboard.clearContents()

        switch item.kind {
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file:
            pasteboard.writeObjects([NSURL(fileURLWithPath: item.content)])
        case .text, .link, .code, .color:
            pasteboard.setString(item.content, forType: .string)
        }

        changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isWritingProgrammatically = false
        }
    }

    func copyAndPaste(_ item: ClipboardItem) {
        copy(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.sendCommandV()
        }
    }

    /// Writes a plain-text string to the pasteboard (for "paste as plain text").
    func copyString(_ string: String) {
        isWritingProgrammatically = true
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isWritingProgrammatically = false
        }
    }

    private func poll(onCapture: @escaping (ClipboardItem) -> Void) {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        guard !isWritingProgrammatically, let item = readCurrentItem() else { return }
        onCapture(item)
    }

    private func readCurrentItem() -> ClipboardItem? {
        let source = NSWorkspace.shared.frontmostApplication
        let appName = source?.localizedName ?? "Unknown App"
        let bundleID = source?.bundleIdentifier
        let appIconData = Self.compactPNG(source?.icon, side: 40)

        // 1. File URL. If it points at an image file, capture it as an image (with a
        //    preview) rather than a bare path — copying an image often arrives this way.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first,
           firstURL.isFileURL {
            if let imageData = Self.imageData(fromFile: firstURL) {
                return ClipboardItem(kind: .image, content: firstURL.lastPathComponent, imageData: imageData, appIconData: appIconData, sourceAppName: appName, sourceBundleIdentifier: bundleID)
            }
            return ClipboardItem(kind: .file, content: firstURL.path, appIconData: appIconData, sourceAppName: appName, sourceBundleIdentifier: bundleID)
        }

        // 2. Inline image data (screenshots, copied image content). Checked before text
        //    because apps such as browsers attach a URL/alt string alongside an image.
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           NSImage(data: data) != nil {
            return ClipboardItem(kind: .image, content: "Image", imageData: data, appIconData: appIconData, sourceAppName: appName, sourceBundleIdentifier: bundleID)
        }

        // 3. Text / link / code / color.
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let kind = ClipboardClassifier.classify(string)
            return ClipboardItem(kind: kind, content: string, appIconData: appIconData, sourceAppName: appName, sourceBundleIdentifier: bundleID)
        }

        return nil
    }

    private static func imageData(fromFile url: URL) -> Data? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let data = try? Data(contentsOf: url),
              NSImage(data: data) != nil else {
            return nil
        }
        return data
    }

    /// Downscales an app icon to a small PNG. Storing the full TIFF representation
    /// bloated the on-disk library and made every card re-decode a large image.
    private static func compactPNG(_ image: NSImage?, side: CGFloat) -> Data? {
        guard let image else { return nil }
        let size = NSSize(width: side, height: side)
        let resized = NSImage(size: size)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
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
