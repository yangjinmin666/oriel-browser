import Foundation

extension AppModel {
    func startBrowser(
        profileId: String = "account-1"
    ) {
        Task {
            guard let profileState = profileState(profileId),
                  let browser = selectedBrowser(for: profileId) else {
                lastError = L10n.text("error.browser.not_detected")
                return
            }
            guard FileManager.default.isExecutableFile(atPath: browser.executablePath) else {
                lastError = L10n.format("error.browser.executable_missing", browser.name)
                return
            }
            busy = true
            lastError = nil
            if await endpointReady(profileId: profileId) {
                updateProfile(profileId) {
                    $0.connected = true
                }
                message = L10n.text("message.browser.already_connected")
                busy = false
                return
            }
            do {
                try saveConfiguration(profileId: profileId)
                let profile = browserDataDirectory(
                    for: profileId,
                    browser: browser
                )
                try FileManager.default.createDirectory(
                    at: profile,
                    withIntermediateDirectories: true
                )
                let process = Process()
                process.executableURL = URL(fileURLWithPath: browser.executablePath)
                process.arguments = [
                    "--remote-debugging-port=\(profileState.port)",
                    "--remote-debugging-address=127.0.0.1",
                    "--user-data-dir=\(profile.path)",
                    "--no-first-run",
                    "--no-default-browser-check",
                    "about:blank"
                ]
                try process.run()
                for _ in 0..<40 {
                    if await endpointReady(profileId: profileId) {
                        updateProfile(profileId) {
                            $0.connected = true
                        }
                        message = L10n.text("message.browser.connected_login")
                        busy = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                busy = false
                lastError = L10n.text("error.browser.start_timeout")
            } catch {
                busy = false
                lastError = error.localizedDescription
            }
        }
    }

    func stopBrowser(
        profileId: String = "account-1"
    ) {
        busy = true
        lastError = nil
        Task {
            do {
                let version = try await debuggerVersion(
                    profileId: profileId
                )
                guard let socketURL = URL(string: version.webSocketDebuggerURL) else {
                    throw browserControlEndpointError()
                }
                let socket = URLSession.shared.webSocketTask(with: socketURL)
                socket.resume()
                try await socket.send(
                    .string(#"{"id":1,"method":"Browser.close"}"#)
                )
                socket.cancel(with: .normalClosure, reason: nil)
                for _ in 0..<20 {
                    if !(await endpointReady(profileId: profileId)) {
                        updateProfile(profileId) {
                            $0.connected = false
                            $0.daemonRunning = false
                            $0.daemonClientCount = 0
                        }
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
