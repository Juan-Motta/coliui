import AppKit
import SwiftUI

@main
struct ColiUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Not `@State`: on the macOS 27 SDK it is a macro whose plugin ships only with Xcode,
    // and this project builds with the Command Line Tools. UI state lives in @Observable models.
    private let model = AppModel.shared

    var body: some Scene {
        Window("ColiUI", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 620)
                .task { model.startPolling() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1232, height: 752)

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(nsImage: Glyph.menuBarImage(dimmed: !model.colima.isRunning))
        }
        .menuBarExtraStyle(.window)

        Settings {
            ContentUnavailableView(
                "Settings",
                systemImage: "gearshape",
                description: Text("Designed, not built yet.")
            )
            .frame(width: 480, height: 320)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
