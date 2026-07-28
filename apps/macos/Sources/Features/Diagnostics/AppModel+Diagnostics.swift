extension AppModel {
    func runHealthCheck() {
        Task {
            busy = true
            browserConnected = await endpointReady()
            refresh()
            if browserConnected && cliInstalled && skillInstalled {
                message = L10n.text("message.diagnostics.passed")
                lastError = nil
            } else {
                lastError = L10n.text("error.diagnostics.incomplete")
            }
            busy = false
        }
    }
}
