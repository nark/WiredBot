import AppKit
import SwiftUI

@main
struct WiredBotApplication: App {
    @StateObject private var model: WiredBotAppViewModel
    @NSApplicationDelegateAdaptor(WiredBotAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        let model = WiredBotAppViewModel()
        _model = StateObject(wrappedValue: model)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await model.refreshAll()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Wired Bot", systemImage: model.menuBarSymbolName) {
            WiredBotMenuView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Wired Bot", id: "configuration") {
            WiredBotConfigurationView()
                .environmentObject(model)
                .frame(minWidth: 900, idealWidth: 980, minHeight: 620, idealHeight: 700)
                .task {
                    appDelegate.model = model
                    model.startPolling()
                    await model.refreshAll()
                }
                .onDisappear {
                    model.stopPolling()
                }
        }
        .defaultSize(width: 980, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Wired Bot") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Open Configuration") {
                    openWindow(id: "configuration")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class WiredBotAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: WiredBotAppViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        return model.confirmDiscardUnsavedChanges(
            message: "You have unsaved changes. Save them before quitting?"
        ) ? .terminateNow : .terminateCancel
    }
}
