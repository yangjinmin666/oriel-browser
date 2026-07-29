import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let primaryProfileId = "account-1"
    static let secondaryProfileId = "account-2"

    let browsers = [
        BrowserChoice(
            id: "chrome",
            name: "Google Chrome",
            appPaths: BrowserChoice.standardAppPaths(named: "Google Chrome"),
            executableName: "Google Chrome",
            symbol: "globe"
        ),
        BrowserChoice(
            id: "tabbit",
            name: "Tabbit",
            appPaths: BrowserChoice.standardAppPaths(named: "Tabbit"),
            executableName: "Tabbit",
            symbol: "rectangle.stack"
        ),
        BrowserChoice(
            id: "edge",
            name: "Microsoft Edge",
            appPaths: BrowserChoice.standardAppPaths(named: "Microsoft Edge"),
            executableName: "Microsoft Edge",
            symbol: "network"
        )
    ]

    @Published var browserProfiles: [BrowserProfileState]
    @Published var cliInstalled = false
    @Published var skillInstalled = false
    @Published var taskSpaces: [TaskSpaceSummary] = []
    @Published var taskSpacesLoading = false
    @Published var busy = false
    @Published var message = L10n.text("message.environment.checking")
    @Published var lastError: String?

    var selectedBrowserId: String {
        profileState(Self.primaryProfileId)?.selectedBrowserId ?? "chrome"
    }

    var selectedBrowser: BrowserChoice? {
        selectedBrowser(for: Self.primaryProfileId)
    }

    var browserConnected: Bool {
        browserProfiles.contains(where: \.connected)
    }

    var allBrowserProfilesConnected: Bool {
        !browserProfiles.isEmpty
            && browserProfiles.allSatisfy(\.connected)
    }

    var daemonRunning: Bool {
        browserProfiles.contains(where: \.daemonRunning)
    }

    var daemonClientCount: Int {
        browserProfiles.reduce(0) { $0 + $1.daemonClientCount }
    }

    var configurationValid: Bool {
        browserProfiles.allSatisfy(\.configurationValid)
    }

    var connectionPort: Int {
        profileState(Self.primaryProfileId)?.port ?? 9765
    }

    var endpoint: String {
        profileState(Self.primaryProfileId)?.endpoint
            ?? "http://127.0.0.1:\(connectionPort)"
    }

    var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/\(Brand.supportDirectoryName)",
                isDirectory: true
            )
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
                    try? FileManager.default.moveItem(
                        at: legacySupport,
                        to: support
                    )
                    break
                }
            }
        }

        func loadConfiguration(_ name: String) -> RuntimeConfiguration? {
            let url = support.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? JSONDecoder().decode(
                RuntimeConfiguration.self,
                from: data
            )
        }

        func validPort(_ value: Int?) -> Int? {
            guard let value, (12_000...49_000).contains(value) else {
                return nil
            }
            return value
        }

        let primaryConfig = loadConfiguration("config.json")
        let secondaryConfig = loadConfiguration("config.account-2.json")
        let primaryPort = validPort(primaryConfig?.port)
            ?? Int.random(in: 12_000...48_000)
        var secondaryPort = validPort(secondaryConfig?.port)
            ?? min(primaryPort + 1, 49_000)
        if secondaryPort == primaryPort {
            secondaryPort = primaryPort == 49_000
                ? primaryPort - 1
                : primaryPort + 1
        }

        let installedBrowserIds = Set(
            browsers.filter(\.installed).map(\.id)
        )
        let primaryBrowserId: String
        if let saved = primaryConfig?.browserId,
           installedBrowserIds.contains(saved) {
            primaryBrowserId = saved
        } else if installedBrowserIds.contains("tabbit") {
            primaryBrowserId = "tabbit"
        } else {
            primaryBrowserId = browsers.first(where: \.installed)?.id
                ?? "chrome"
        }

        let secondaryBrowserId: String
        if let saved = secondaryConfig?.browserId,
           installedBrowserIds.contains(saved) {
            secondaryBrowserId = saved
        } else if installedBrowserIds.contains("chrome"),
                  primaryBrowserId != "chrome" {
            secondaryBrowserId = "chrome"
        } else {
            secondaryBrowserId = browsers.first(
                where: {
                    $0.installed && $0.id != primaryBrowserId
                }
            )?.id ?? primaryBrowserId
        }

        browserProfiles = [
            BrowserProfileState(
                id: Self.primaryProfileId,
                label: L10n.text("browser_profile.account_1"),
                selectedBrowserId: primaryBrowserId,
                port: primaryPort
            ),
            BrowserProfileState(
                id: Self.secondaryProfileId,
                label: L10n.text("browser_profile.account_2"),
                selectedBrowserId: secondaryBrowserId,
                port: secondaryPort
            ),
        ]
        try? saveAllConfigurations()
    }

    func profileState(_ profileId: String) -> BrowserProfileState? {
        browserProfiles.first(where: { $0.id == profileId })
    }

    func selectedBrowser(for profileId: String) -> BrowserChoice? {
        guard let profile = profileState(profileId) else {
            return nil
        }
        return browsers.first(
            where: {
                $0.id == profile.selectedBrowserId && $0.installed
            }
        ) ?? browsers.first(where: \.installed)
    }

    func updateProfile(
        _ profileId: String,
        _ update: (inout BrowserProfileState) -> Void
    ) {
        guard let index = browserProfiles.firstIndex(
            where: { $0.id == profileId }
        ) else {
            return
        }
        var profile = browserProfiles[index]
        update(&profile)
        browserProfiles[index] = profile
    }

    func refresh() {
        Task {
            await refreshStatus()
        }
    }

    func refreshStatus() async {
        var refreshed = browserProfiles
        for index in refreshed.indices {
            let profileId = refreshed[index].id
            let report = await loadDoctorReport(profileId: profileId)
            let endpointConnected = await endpointReady(profileId: profileId)
            refreshed[index].connected =
                report?.browser.connected ?? endpointConnected
            refreshed[index].daemonRunning =
                report?.daemon.running ?? false
            refreshed[index].daemonClientCount =
                report?.daemon.clients ?? 0
            refreshed[index].configurationValid =
                report?.configuration.valid ?? true
        }
        browserProfiles = refreshed

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
            message = L10n.text(
                "message.diagnostics.configuration_needs_repair"
            )
        } else if allBrowserProfilesConnected {
            message = L10n.text("message.browser.profiles_connected")
        } else if browserConnected {
            message = L10n.text("message.browser.profile_partially_connected")
        } else if browsers.first(where: \.installed) == nil {
            message = L10n.text("message.browser.none_detected")
        } else {
            message = L10n.text("message.browser.ready")
        }

        if browserConnected {
            taskSpaces = await loadAllTaskSpaces()
        } else {
            taskSpaces = []
        }
    }

    func refreshTaskSpaces() {
        guard browserConnected, !taskSpacesLoading else {
            return
        }
        taskSpacesLoading = true
        Task {
            taskSpaces = await loadAllTaskSpaces()
            taskSpacesLoading = false
        }
    }

    func select(
        _ browser: BrowserChoice,
        profileId: String = "account-1"
    ) {
        guard let profile = profileState(profileId) else {
            return
        }
        if profile.connected && browser.id != profile.selectedBrowserId {
            lastError = L10n.format(
                "error.browser.switch_requires_stop",
                browser.name
            )
            return
        }
        updateProfile(profileId) {
            $0.selectedBrowserId = browser.id
        }
        do {
            try saveConfiguration(profileId: profileId)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func endpointReady(
        profileId: String = "account-1"
    ) async -> Bool {
        do {
            _ = try await debuggerVersion(profileId: profileId)
            return true
        } catch {
            return false
        }
    }

    func debuggerVersion(
        profileId: String = "account-1"
    ) async throws -> BrowserDebugVersion {
        guard let profile = profileState(profileId),
              let endpointURL = URL(string: profile.endpoint) else {
            throw browserControlEndpointError()
        }
        var request = URLRequest(
            url: endpointURL.appendingPathComponent("json/version")
        )
        request.timeoutInterval = 1.2
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let version = try? JSONDecoder().decode(
                  BrowserDebugVersion.self,
                  from: data
              ),
              version.isTrusted(for: endpointURL) else {
            throw browserControlEndpointError()
        }
        return version
    }

    func browserControlEndpointError() -> NSError {
        NSError(
            domain: "Oriel",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey: L10n.text(
                    "error.browser.control_endpoint_missing"
                )
            ]
        )
    }

    func configurationURL(for profileId: String) -> URL {
        let fileName = profileId == Self.primaryProfileId
            ? "config.json"
            : "config.\(profileId).json"
        return supportDirectory.appendingPathComponent(fileName)
    }

    func browserDataDirectory(
        for profileId: String,
        browser: BrowserChoice
    ) -> URL {
        let directoryName = profileId == Self.primaryProfileId
            ? browser.id
            : profileId
        return supportDirectory
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    @discardableResult
    func saveConfiguration(
        profileId: String = "account-1"
    ) throws -> RuntimeConfiguration {
        guard let profile = profileState(profileId),
              let browser = selectedBrowser(for: profileId) else {
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
        let browserData = browserDataDirectory(
            for: profileId,
            browser: browser
        )
        let config = RuntimeConfiguration(
            profileId: profile.id,
            profileLabel: profile.label,
            browserId: browser.id,
            browserName: browser.name,
            browserPath: browser.executablePath,
            endpoint: profile.endpoint,
            port: profile.port,
            profilePath: browserData.path,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(
            to: configurationURL(for: profileId),
            options: .atomic
        )
        return config
    }

    func saveAllConfigurations() throws {
        for profile in browserProfiles {
            try saveConfiguration(profileId: profile.id)
        }
    }

    func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func loadDoctorReport(
        profileId: String
    ) async -> DoctorReport? {
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
            return nil
        }

        return await Task.detached {
            let output = Pipe()
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [entryURL.path, "--doctor", "--json"]
            var environment = ProcessInfo.processInfo.environment
            environment["ORIEL_PROFILE_ID"] = profileId
            process.environment = environment
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return try? JSONDecoder().decode(
                    DoctorReport.self,
                    from: data
                )
            } catch {
                return nil
            }
        }.value
    }

    private func loadAllTaskSpaces() async -> [TaskSpaceSummary] {
        var allSpaces: [TaskSpaceSummary] = []
        for profile in browserProfiles
        where profile.connected && profile.daemonRunning {
            allSpaces.append(
                contentsOf: await loadTaskSpaces(profileId: profile.id)
            )
        }
        return allSpaces
    }

    private func loadTaskSpaces(
        profileId: String
    ) async -> [TaskSpaceSummary] {
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
            return []
        }

        return await Task.detached {
            let output = Pipe()
            let input = Pipe()
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [entryURL.path, "nodejs"]
            var environment = ProcessInfo.processInfo.environment
            environment["ORIEL_PROFILE_ID"] = profileId
            process.environment = environment
            process.standardInput = input
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                let program = """
                console.log(JSON.stringify(await taskSpaces.list()))
                """
                input.fileHandleForWriting.write(Data(program.utf8))
                try? input.fileHandleForWriting.close()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    return []
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8) else {
                    return []
                }
                for line in text.split(separator: "\n").reversed() {
                    guard let lineData = String(line).data(using: .utf8),
                          var spaces = try? JSONDecoder().decode(
                              [TaskSpaceSummary].self,
                              from: lineData
                          ) else {
                        continue
                    }
                    for index in spaces.indices {
                        spaces[index].profileId = profileId
                    }
                    return spaces
                }
                return []
            } catch {
                return []
            }
        }.value
    }
}
