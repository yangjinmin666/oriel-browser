import Foundation

extension AppModel {
    func runHealthCheck() {
        Task {
            busy = true
            await refreshStatus()
            if browserConnected && cliInstalled && skillInstalled && configurationValid {
                message = L10n.text("message.diagnostics.passed")
                lastError = nil
            } else {
                lastError = L10n.text("error.diagnostics.incomplete")
            }
            busy = false
        }
    }

    func repairConnection() {
        Task {
            busy = true
            lastError = nil
            do {
                _ = try saveConfiguration()
                await stopDaemonIfRunning()
                await refreshStatus()
                message = L10n.text("message.diagnostics.repaired")
            } catch {
                lastError = error.localizedDescription
            }
            busy = false
        }
    }

    private func stopDaemonIfRunning() async {
        guard let nodeURL = Bundle.main.url(
            forResource: "node",
            withExtension: nil,
            subdirectory: "Runtime/bin"
        ),
            let entryURL = Bundle.main.url(
                forResource: "oriel",
                withExtension: "mjs",
                subdirectory: "Runtime"
            )
        else {
            return
        }

        await Task.detached {
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [entryURL.path, "--daemon-stop"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }
        }.value
    }
}
