import SwiftUI

struct WiredBotMenuView: View {
    @EnvironmentObject private var model: WiredBotAppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.installState.title, systemImage: model.menuBarSymbolName)
                .foregroundStyle(model.installState.color)

            Divider()

            Label(model.modelTitle, systemImage: "brain.head.profile")
            Label("\(model.providerTitle): \(model.providerStatus.title)", systemImage: providerSymbol)
                .foregroundStyle(model.providerStatus.color)

            Divider()

            Button("Open Configuration") {
                openWindow(id: "configuration")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button(model.installState == .running ? "Stop Bot" : "Start Bot") {
                Task {
                    if model.installState == .running {
                        await model.stopBotFromUI()
                    } else {
                        await model.startBot()
                    }
                }
            }

            Button("Restart Bot") {
                Task { await model.restartBot() }
            }
            .disabled(model.installState != .running)

            Button("Check Provider") {
                Task { await model.checkProvider() }
            }

            Divider()

            Button("Quit Wired Bot") {
                NSApplication.shared.terminate(nil)
            }
        }
        .task {
            await model.refreshMenu()
        }
    }

    private var providerSymbol: String {
        model.providerStatus.isAvailable ? "checkmark.circle.fill" : "network"
    }
}
