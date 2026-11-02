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
        .commands {
            // ⌘, opens the Settings sheet on the main window instead of a separate window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.isSettingsPresented = true }
                    .keyboardShortcut(",")
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(nsImage: Glyph.menuBarImage(dimmed: !model.colima.isRunning))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock icon and theme from Settings; also needed when launched as a bare executable (`swift run`).
        MainActor.assumeIsolated { AppModel.shared.applySystemSettings() }
        NSApp.activate()
    }
}
