import Foundation

enum Brand {
    static let displayName = "Oriel"
    static let supportDirectoryName = "Oriel"
    static let legacySupportDirectoryNames = ["ZhiYou", "Ego Anywhere"]
    static let cliName = "oriel"
    static let legacyCLINames = ["zhiyou", "ego-anywhere"]
    static let skillName = "oriel-browser"
    static let legacySkillNames = ["zhiyou-browser", "ego-anywhere"]
}

struct BrowserChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let appPath: String
    let executablePath: String
    let symbol: String

    var installed: Bool {
        FileManager.default.fileExists(atPath: appPath)
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
