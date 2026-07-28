import AppKit
import SwiftUI

@main
struct OrielApp: App {
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
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
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
