import AppKit
import SwiftUI

struct WindowBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }
            window.isMovableByWindowBackground = true
        }
    }
}
