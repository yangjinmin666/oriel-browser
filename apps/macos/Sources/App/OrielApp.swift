import AppKit
import SwiftUI

final class OrielApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        revealMainWindow()
    }

    private func revealMainWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = NSApp.windows.first else {
                return
            }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct OrielApp: App {
    @NSApplicationDelegateAdaptor(OrielApplicationDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ControlCenterView()
                        .environmentObject(model)
                } else {
                    WelcomeView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            hasCompletedOnboarding = true
                        }
                    }
                }
            }
            .background(WindowBehavior())
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            Text(
                model.browserConnected
                    ? L10n.text("menu.status.connected")
                    : L10n.text("menu.status.disconnected")
            )
            Divider()
            Button(L10n.text("menu.control_center")) {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first {
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Button(L10n.text("menu.refresh")) {
                model.refresh()
            }
            Divider()
            Button(L10n.text("menu.quit")) {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: model.browserConnected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
        }
    }
}
