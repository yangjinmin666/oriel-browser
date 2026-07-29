import Foundation

enum Brand {
    static let displayName = "Oriel"
    static let supportDirectoryName = "Oriel"
    static let legacySupportDirectoryNames = ["ZhiYou", "Ego Anywhere"]
    static let cliName = "oriel"
    static let legacyCLINames = ["zhiyou", "ego-anywhere"]
    static let skillName = "oriel-browser"
    static let legacySkillNames = ["zhiyou-browser", "ego-anywhere"]

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
    let browserId: String
    let browserName: String
    let browserPath: String
    let endpoint: String
    let port: Int
    let profilePath: String
    let updatedAt: String
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
    let status: String
    let configuration: Configuration
    let browser: Browser
    let daemon: Daemon
}

struct TaskSpaceSummary: Decodable, Identifiable, Hashable, Sendable {
    let taskId: String
    let id: Int
    let name: String
    let createdBy: String?
    let ownership: String?
    let recentTabTitles: [String]

    var isAgentOwned: Bool {
        ownership == "agent"
    }
}
