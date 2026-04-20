import AppKit
import SwiftUI

struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var model: WiredBotAppViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.model = model
        DispatchQueue.main.async {
            view.window?.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var model: WiredBotAppViewModel

        init(model: WiredBotAppViewModel) {
            self.model = model
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            model.confirmDiscardUnsavedChanges(
                message: "You have unsaved changes. Save them before closing?"
            )
        }
    }
}
