import AppKit

/// Softer scroll bars: every NSScroller in the app (SwiftUI's ScrollViews included) draws at reduced opacity.
/// AppKit has no knob colour setting, so this hooks `viewDidMoveToWindow` once and lowers the scroller's alpha;
/// the overlay scroller still fades in and out on its own on top of that.
extension NSScroller {
    static let knobOpacity: CGFloat = 0.6

    @MainActor static let installSubtleKnobs: Void = {
        let cls: AnyClass = NSScroller.self
        let original = #selector(NSView.viewDidMoveToWindow)
        let replacement = #selector(NSScroller.coliui_viewDidMoveToWindow)
        guard let originalMethod = class_getInstanceMethod(cls, original),
              let replacementMethod = class_getInstanceMethod(cls, replacement) else { return }
        // NSScroller may inherit the method from NSView: add it to NSScroller first so only scrollers change.
        if class_addMethod(cls, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod)) {
            class_replaceMethod(cls, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }()

    @objc private func coliui_viewDidMoveToWindow() {
        coliui_viewDidMoveToWindow() // the original, after the exchange
        alphaValue = Self.knobOpacity
    }
}
