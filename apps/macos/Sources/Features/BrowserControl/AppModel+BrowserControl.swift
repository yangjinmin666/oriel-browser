import Foundation

extension AppModel {
    func startBrowser() {
        guard let browser = selectedBrowser else {
            lastError = L10n.text("error.browser.not_detected")
            return
        }
        busy = true
        lastError = nil
        do {
            try saveConfiguration()
            let profile = supportDirectory
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent(browser.id, isDirectory: true)
            try FileManager.default.createDirectory(
                at: profile,
                withIntermediateDirectories: true
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: browser.executablePath)
            process.arguments = [
                "--remote-debugging-port=\(connectionPort)",
                "--remote-debugging-address=127.0.0.1",
                "--user-data-dir=\(profile.path)",
                "--no-first-run",
                "--no-default-browser-check",
                "about:blank"
            ]
            try process.run()
            Task {
                for _ in 0..<40 {
                    if await endpointReady() {
                        browserConnected = true
                        message = L10n.text("message.browser.connected_login")
                        busy = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                busy = false
                lastError = L10n.text("error.browser.start_timeout")
            }
        } catch {
            busy = false
            lastError = error.localizedDescription
        }
    }

    func stopBrowser() {
        busy = true
        lastError = nil
        Task {
            do {
                guard let versionURL = URL(string: "\(endpoint)/json/version") else {
                    throw URLError(.badURL)
                }
                let (data, _) = try await URLSession.shared.data(from: versionURL)
                guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let socketAddress = payload["webSocketDebuggerUrl"] as? String,
                      let socketURL = URL(string: socketAddress) else {
                    throw NSError(
                        domain: "Oriel",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: L10n.text(
                                "error.browser.control_endpoint_missing"
                            )
                        ]
                    )
                }
                let socket = URLSession.shared.webSocketTask(with: socketURL)
                socket.resume()
                try await socket.send(
                    .string(#"{"id":1,"method":"Browser.close"}"#)
                )
                socket.cancel(with: .normalClosure, reason: nil)
                for _ in 0..<20 {
                    if !(await endpointReady()) {
                        browserConnected = false
                        message = L10n.text("message.browser.stopped")
                        busy = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                throw NSError(
                    domain: "Oriel",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey: L10n.text(
                            "error.browser.stop_timeout"
                        )
                    ]
                )
            } catch {
                lastError = error.localizedDescription
                busy = false
            }
        }
    }
}
