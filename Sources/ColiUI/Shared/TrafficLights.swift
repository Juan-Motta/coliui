import AppKit
import SwiftUI

/// Moves the window's traffic lights into the sidebar panel's top row, as drawn in the designs:
/// panel margin 8 pt + padding 16 pt (left) / 14 pt (top), 12 pt dots 8 pt apart.
/// AppKit lays the title bar out again on resize, focus and full screen, so the position is reapplied then.
struct TrafficLightsPositioner: NSViewRepresentable {
    /// Left edge of the close dot, from the window's left edge.
    var leading: CGFloat = 24
    /// Centre of the dots, from the window's top edge.
    var centerY: CGFloat = 28
    /// Only the sidebar's width keeps the enlarged title bar, so the header controls stay clickable.
    var width: CGFloat = 240

    func makeNSView(context: Context) -> PositionerView {
        let view = PositionerView()
        view.configuration = (leading, centerY, width)
        return view
    }

    func updateNSView(_ view: PositionerView, context: Context) {
        view.configuration = (leading, centerY, width)
        view.reposition()
    }

    final class PositionerView: NSView {
        var configuration: (leading: CGFloat, centerY: CGFloat, width: CGFloat) = (24, 28, 240)
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reposition() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.reposition() }
        }

        func reposition() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview,
                  let container = titlebar.superview,
                  let frameView = container.superview else { return }

            let height = configuration.centerY * 2
            container.frame = NSRect(
                x: 0,
                y: frameView.bounds.height - height,
                width: configuration.width,
                height: height
            )
            titlebar.frame = container.bounds

            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in buttons.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let dotInset = (button.frame.width - 12) / 2
                button.setFrameOrigin(NSPoint(
                    x: configuration.leading - dotInset + CGFloat(index) * 20,
                    y: (height - button.frame.height) / 2
                ))
            }
        }
    }
}
