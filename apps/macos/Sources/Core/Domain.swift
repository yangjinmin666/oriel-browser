import Foundation

enum Brand {
    static let displayName = "Oriel"
    static let supportDirectoryName = "Oriel"
    static let legacySupportDirectoryNames = ["ZhiYou"]
    static let cliName = "oriel"
    static let legacyCLINames = ["zhiyou"]
    static let skillName = "oriel-browser"
    static let compatibilitySkillName = "ego-browser"
    static let installedSkillNames = [skillName, compatibilitySkillName]
    static let conflictingSkillNames = ["zhiyou-browser"]
    static let agentSkillRootRelativePaths = [".codex/skills", ".claude/skills"]

    static var releaseLabel: String {
        let release = (
            Bundle.main.object(forInfoDictionaryKey: "OrielReleaseLabel") as? String
        ) ?? (
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ) ?? "0.0.0"
        return "v\(release)"
    }
}

struct BrowserChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let appPaths: [String]
    let executableName: String
    let symbol: String

    static func standardAppPaths(named appName: String) -> [String] {
        [
            "/Applications/\(appName).app",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/\(appName).app").path,
        ]
    }

    private var discoveredAppPath: String? {
        appPaths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    var appPath: String {
        discoveredAppPath ?? appPaths[0]
    }

    var executablePath: String {
        URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/MacOS/\(executableName)").path
    }

    var installed: Bool {
        discoveredAppPath != nil
    }
}

struct BrowserDebugVersion: Decodable {
    let browser: String
    let webSocketDebuggerURL: String

    enum CodingKeys: String, CodingKey {
        case browser = "Browser"
        case webSocketDebuggerURL = "webSocketDebuggerUrl"
    }

    func isTrusted(for endpoint: URL) -> Bool {
        guard !browser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let socketURL = URL(string: webSocketDebuggerURL),
              socketURL.scheme?.lowercased() == "ws",
              BrowserDebugVersion.isLoopback(endpoint.host),
              BrowserDebugVersion.isLoopback(socketURL.host),
              endpoint.port == socketURL.port else {
            return false
        }
        return true
    }

    private static func isLoopback(_ host: String?) -> Bool {
        switch host?.lowercased() {
        case "127.0.0.1", "localhost", "::1", "[::1]":
            return true
        default:
            return false
        }
    }
}

struct RuntimeConfiguration: Codable {
    let profileId: String?
    let profileLabel: String?
    let browserId: String
    let browserName: String
    let browserPath: String
    let endpoint: String
    let port: Int
    let profilePath: String
    let updatedAt: String
}

struct BrowserProfileState: Identifiable, Hashable {
    let id: String
    let label: String
    var selectedBrowserId: String
    let port: Int
    var connected: Bool = false
    var daemonRunning: Bool = false
    var daemonClientCount: Int = 0
    var configurationValid: Bool = true

    var endpoint: String {
        "http://127.0.0.1:\(port)"
    }
}

struct DoctorReport: Decodable, Sendable {
    struct Configuration: Decodable, Sendable {
        let valid: Bool
        let browserId: String?
        let browserName: String?
        let endpoint: String?
        let error: String?
    }

    struct Browser: Decodable, Sendable {
        let connected: Bool
    }

    struct Daemon: Decodable, Sendable {
        let running: Bool
        let pid: Int?
        let clients: Int?
    }

    let schemaVersion: Int
    let profileId: String?
    let status: String
    let configuration: Configuration
    let browser: Browser
    let daemon: Daemon
}

struct TaskSpaceSummary: Decodable, Identifiable, Hashable, Sendable {
    struct Lifecycle: Decodable, Hashable, Sendable {
        struct Failure: Decodable, Hashable, Sendable {
            let code: String
            let safeRecovery: String
        }

        let status: String?
        let stage: String?
        let startedAt: String?
        let endedAt: String?
        let approvalAvailable: Bool?
        let lastFailure: Failure?
    }

    let taskId: String
    let runtimeId: Int
    let name: String
    let createdBy: String?
    let ownership: String?
    let recentTabTitles: [String]
    let executionPolicy: String?
    let lifecycle: Lifecycle?
    let auditEventCount: Int?
    var profileId = "account-1"

    var id: String {
        "\(profileId):\(runtimeId)"
    }

    enum CodingKeys: String, CodingKey {
        case taskId
        case runtimeId = "id"
        case name
        case createdBy
        case ownership
        case recentTabTitles
        case executionPolicy
        case lifecycle
        case auditEventCount
    }

    var isAgentOwned: Bool {
        ownership == "agent"
    }

    var executionPolicyValue: String {
        executionPolicy ?? "requires-approval"
    }

    var lifecycleStatus: String {
        lifecycle?.status ?? "running"
    }

    var requiresRecovery: Bool {
        lifecycle?.lastFailure != nil
    }
}

struct TaskAuditEvent: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let at: String
    let runtimeId: Int
    let type: String
    let actor: String?
    let action: String?
    let code: String?
    let safeRecovery: String?
    var profileId = "account-1"

    enum CodingKeys: String, CodingKey {
        case id
        case at
        case runtimeId
        case type
        case actor
        case action
        case code
        case safeRecovery
    }
}

struct TaskAuditResponse: Decodable, Sendable {
    var events: [TaskAuditEvent]
}
