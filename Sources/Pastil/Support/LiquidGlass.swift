import AppKit
import SwiftUI

/// A frosted "liquid glass" backdrop that blurs the desktop and windows sitting
/// behind the shelf panel. The panel window itself is transparent, so this is what
/// gives the tray its glass look on macOS 26 (and a graceful blur on earlier systems).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

@available(macOS 26.0, *)
private func makeLiquidGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = .regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// Applies genuine Liquid Glass on macOS 26+, falling back to a frosted material
    /// on earlier systems. Used for the chrome (search field, scope chips, buttons).
    @ViewBuilder
    func liquidGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(makeLiquidGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
