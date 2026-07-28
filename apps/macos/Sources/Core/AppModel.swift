import Foundation

@MainActor
final class AppModel: ObservableObject {
    let browsers = [
        BrowserChoice(
            id: "chrome",
            name: "Google Chrome",
            appPath: "/Applications/Google Chrome.app",
            executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            symbol: "globe"
        ),
        BrowserChoice(
            id: "tabbit",
            name: "Tabbit",
            appPath: "/Applications/Tabbit.app",
            executablePath: "/Applications/Tabbit.app/Contents/MacOS/Tabbit",
            symbol: "rectangle.stack"
        ),
        BrowserChoice(
            id: "edge",
            name: "Microsoft Edge",
            appPath: "/Applications/Microsoft Edge.app",
            executablePath: "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            symbol: "network"
        )
    ]

    @Published var selectedBrowserId = "chrome"
    @Published var browserConnected = false
    @Published var daemonRunning = false
    @Published var daemonClientCount = 0
    @Published var configurationValid = true
    @Published var cliInstalled = false
    @Published var skillInstalled = false
    @Published var busy = false
    @Published var message = L10n.text("message.environment.checking")
    @Published var lastError: String?

    let connectionPort: Int
    let endpoint: String

    var selectedBrowser: BrowserChoice? {
        browsers.first(where: { $0.id == selectedBrowserId && $0.installed })
            ?? browsers.first(where: \.installed)
    }

    var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/\(Brand.supportDirectoryName)",
                isDirectory: true
            )
    }

    private var configurationURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent(
            "Library/Application Support/\(Brand.supportDirectoryName)",
            isDirectory: true
        )
        if !FileManager.default.fileExists(atPath: support.path) {
            for legacyName in Brand.legacySupportDirectoryNames {
                let legacySupport = home.appendingPathComponent(
                    "Library/Application Support/\(legacyName)",
                    isDirectory: true
                )
                if FileManager.default.fileExists(atPath: legacySupport.path) {
                    try? FileManager.default.moveItem(at: legacySupport, to: support)
                    break
                }
            }
        }

        let configURL = support.appendingPathComponent("config.json")
        let savedData = try? Data(contentsOf: configURL)
        let savedConfig = savedData.flatMap {
            try? JSONDecoder().decode(RuntimeConfiguration.self, from: $0)
        }
        let savedPort = savedConfig?.port ?? 0
        connectionPort = (12_000...49_000).contains(savedPort)
            ? savedPort
            : Int.random(in: 12_000...49_000)
        endpoint = "http://127.0.0.1:\(connectionPort)"

        if let config = savedConfig,
           browsers.contains(where: { $0.id == config.browserId && $0.installed }) {
            selectedBrowserId = config.browserId
        } else if !browsers[0].installed, let first = browsers.first(where: \.installed) {
            selectedBrowserId = first.id
        }
        _ = try? saveConfiguration()
    }

    func refresh() {
        Task {
            await refreshStatus()
        }
    }

    func refreshStatus() async {
        let report = await loadDoctorReport()
        let endpointConnected = await endpointReady()
        browserConnected = report?.browser.connected ?? endpointConnected
        daemonRunning = report?.daemon.running ?? false
        daemonClientCount = report?.daemon.clients ?? 0
        configurationValid = report?.configuration.valid ?? true
        cliInstalled = FileManager.default.isExecutableFile(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/\(Brand.cliName)").path
        )
        skillInstalled = FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    ".codex/skills/\(Brand.skillName)/SKILL.md"
                ).path
        )
        if !configurationValid {
            message = L10n.text("message.diagnostics.configuration_needs_repair")
        } else if browserConnected {
            message = L10n.text("message.browser.connected")
        } else if selectedBrowser == nil {
            message = L10n.text("message.browser.none_detected")
        } else {
            message = L10n.text("message.browser.ready")
        }
    }

    func select(_ browser: BrowserChoice) {
        if browserConnected && browser.id != selectedBrowserId {
            lastError = L10n.format(
                "error.browser.switch_requires_stop",
                browser.name
            )
            return
        }
        selectedBrowserId = browser.id
        do {
            try saveConfiguration()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func endpointReady() async -> Bool {
        guard let url = URL(string: "\(endpoint)/json/version") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    @discardableResult
    func saveConfiguration() throws -> RuntimeConfiguration {
        guard let browser = selectedBrowser else {
            throw NSError(
                domain: "Oriel",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: L10n.text(
                        "error.browser.not_available"
                    )
                ]
            )
        }
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        let profile = supportDirectory
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(browser.id, isDirectory: true)
        let config = RuntimeConfiguration(
            browserId: browser.id,
            browserName: browser.name,
            browserPath: browser.executablePath,
            endpoint: endpoint,
            port: connectionPort,
            profilePath: profile.path,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configurationURL, options: .atomic)
        return config
    }

    func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func loadDoctorReport() async -> DoctorReport? {
        guard let nodeURL = Bundle.main.url(
            forResource: "node",
            withExtension: nil,
            subdirectory: "Runtime"
        ),
            let entryURL = Bundle.main.url(
                forResource: "oriel",
                withExtension: "mjs",
                subdirectory: "Runtime"
            )
        else {
            return nil
        }

        return await Task.detached {
            let output = Pipe()
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [entryURL.path, "--doctor", "--json"]
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return try? JSONDecoder().decode(DoctorReport.self, from: data)
            } catch {
                return nil
            }
        }.value
    }
}
