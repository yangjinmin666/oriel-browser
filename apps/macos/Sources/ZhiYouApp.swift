import AppKit
import Foundation
import SwiftUI

enum Brand {
    static let displayName = "智游 ZhiYou"
    static let supportDirectoryName = "ZhiYou"
    static let legacySupportDirectoryName = "Ego Anywhere"
    static let cliName = "zhiyou"
    static let legacyCLIName = "ego-anywhere"
    static let skillName = "zhiyou-browser"
    static let legacySkillName = "ego-anywhere"
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
    @Published var cliInstalled = false
    @Published var skillInstalled = false
    @Published var busy = false
    @Published var message = "正在检查本机环境…"
    @Published var lastError: String?

    let connectionPort: Int
    let endpoint: String

    private var selectedBrowser: BrowserChoice? {
        browsers.first(where: { $0.id == selectedBrowserId && $0.installed })
            ?? browsers.first(where: \.installed)
    }

    private var supportDirectory: URL {
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
        let legacySupport = home.appendingPathComponent(
            "Library/Application Support/\(Brand.legacySupportDirectoryName)",
            isDirectory: true
        )
        if !FileManager.default.fileExists(atPath: support.path),
           FileManager.default.fileExists(atPath: legacySupport.path) {
            try? FileManager.default.moveItem(at: legacySupport, to: support)
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
            browserConnected = await endpointReady()
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
            if browserConnected {
                message = "浏览器已连接，Codex 可以开始工作。"
            } else if selectedBrowser == nil {
                message = "没有检测到受支持的 Chromium 浏览器。"
            } else {
                message = "环境已就绪，启动浏览器即可使用。"
            }
        }
    }

    func select(_ browser: BrowserChoice) {
        if browserConnected && browser.id != selectedBrowserId {
            lastError = "请先停止当前浏览器，再切换到 \(browser.name)。"
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

    func startBrowser() {
        guard let browser = selectedBrowser else {
            lastError = "没有检测到 Chrome、Tabbit 或 Edge。"
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
                        message = "浏览器已连接。请在这个浏览器中登录需要使用的网站。"
                        busy = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                busy = false
                lastError = "浏览器已打开，但本地连接没有在 10 秒内就绪。"
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
                        domain: "ZhiYou",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "没有读取到浏览器控制端点。"]
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
                        message = "浏览器已停止。登录状态仍保存在本机。"
                        busy = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                throw NSError(
                    domain: "ZhiYou",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "浏览器没有及时停止，可以直接关闭浏览器窗口。"]
                )
            } catch {
                lastError = error.localizedDescription
                busy = false
            }
        }
    }

    func installCodexIntegration() {
        busy = true
        lastError = nil
        do {
            guard let resources = Bundle.main.resourceURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            let runtime = resources.appendingPathComponent("Runtime", isDirectory: true)
            let node = runtime.appendingPathComponent("bin/node")
            let entry = runtime.appendingPathComponent("zhiyou.mjs")
            guard FileManager.default.isExecutableFile(atPath: node.path),
                  FileManager.default.fileExists(atPath: entry.path) else {
                throw NSError(
                    domain: "ZhiYou",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "应用内置运行时不完整，请重新安装智游。"]
                )
            }

            let binDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin", isDirectory: true)
            try FileManager.default.createDirectory(
                at: binDirectory,
                withIntermediateDirectories: true
            )
            let script = """
            #!/bin/zsh
            exec \(shellQuote(node.path)) \(shellQuote(entry.path)) "$@"
            """
            for commandName in [Brand.cliName, Brand.legacyCLIName] {
                let launcher = binDirectory.appendingPathComponent(commandName)
                try script.write(to: launcher, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: launcher.path
                )
            }

            let skillSource = resources
                .appendingPathComponent("Skill", isDirectory: true)
                .appendingPathComponent(Brand.skillName, isDirectory: true)
            let skillDestination = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    ".codex/skills/\(Brand.skillName)",
                    isDirectory: true
                )
            let legacySkillDestination = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    ".codex/skills/\(Brand.legacySkillName)",
                    isDirectory: true
                )
            if FileManager.default.fileExists(atPath: skillDestination.path) {
                try FileManager.default.removeItem(at: skillDestination)
            }
            if FileManager.default.fileExists(atPath: legacySkillDestination.path) {
                try FileManager.default.removeItem(at: legacySkillDestination)
            }
            try FileManager.default.createDirectory(
                at: skillDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: skillSource, to: skillDestination)
            try saveConfiguration()
            cliInstalled = true
            skillInstalled = true
            message = "智游的 Codex 集成已安装。重新打开 Codex 后即可直接使用。"
        } catch {
            lastError = error.localizedDescription
        }
        busy = false
    }

    func runHealthCheck() {
        Task {
            busy = true
            browserConnected = await endpointReady()
            refresh()
            if browserConnected && cliInstalled && skillInstalled {
                message = "全部检查通过。"
                lastError = nil
            } else {
                lastError = "还有未完成的项目，请按页面顺序处理。"
            }
            busy = false
        }
    }

    private func endpointReady() async -> Bool {
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
    private func saveConfiguration() throws -> RuntimeConfiguration {
        guard let browser = selectedBrowser else {
            throw NSError(
                domain: "ZhiYou",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "没有可用浏览器。"]
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

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct StatusDot: View {
    let ready: Bool

    var body: some View {
        Circle()
            .fill(ready ? Color.green : Color.orange)
            .frame(width: 9, height: 9)
            .accessibilityLabel(ready ? "已就绪" : "未就绪")
    }
}

struct BrowserRow: View {
    let browser: BrowserChoice
    let selected: Bool
    let selectionLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: browser.symbol)
                    .frame(width: 22)
                    .foregroundStyle(browser.installed ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.name)
                    Text(browser.installed ? "已检测到" : "未安装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(!browser.installed || (selectionLocked && !selected))
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Brand.displayName)
                        .font(.system(size: 27, weight: .semibold))
                    Text("AI 浏览器协作台 · 让 Codex 使用你选择的浏览器")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    StatusDot(ready: model.browserConnected && model.cliInstalled && model.skillInstalled)
                    Text(model.browserConnected && model.cliInstalled && model.skillInstalled ? "已就绪" : "配置中")
                        .font(.callout.weight(.medium))
                }
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("1. 选择浏览器", subtitle: "使用独立配置保存登录状态，不读取或导出 Cookie。") {
                        VStack(spacing: 4) {
                            ForEach(model.browsers) { browser in
                                BrowserRow(
                                    browser: browser,
                                    selected: model.selectedBrowserId == browser.id,
                                    selectionLocked: model.browserConnected,
                                    action: { model.select(browser) }
                                )
                            }
                        }
                    }

                    section("2. 启动连接", subtitle: "调试端口仅绑定本机。浏览器运行时，本机程序可控制其中页面。") {
                        HStack {
                            StatusDot(ready: model.browserConnected)
                            Text(model.browserConnected ? "浏览器已连接" : "浏览器尚未连接")
                            Spacer()
                            if model.browserConnected {
                                Button {
                                    model.stopBrowser()
                                } label: {
                                    Label("停止浏览器", systemImage: "stop.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.busy)
                            } else {
                                Button {
                                    model.startBrowser()
                                } label: {
                                    Label("启动浏览器", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.busy)
                            }
                        }
                    }

                    section("3. 安装 Codex 集成", subtitle: "安装本地命令和 skill，所有浏览数据仍保存在这台 Mac。") {
                        HStack {
                            StatusDot(ready: model.cliInstalled && model.skillInstalled)
                            Text(
                                model.cliInstalled && model.skillInstalled
                                    ? "Codex 集成已安装"
                                    : "尚未安装"
                            )
                            Spacer()
                            Button {
                                model.installCodexIntegration()
                            } label: {
                                Label(
                                    model.cliInstalled && model.skillInstalled ? "重新安装" : "一键安装",
                                    systemImage: "square.and.arrow.down"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.busy)
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: model.lastError == nil ? "info.circle" : "exclamationmark.triangle")
                            .foregroundStyle(model.lastError == nil ? Color.blue : Color.orange)
                        Text(model.lastError ?? model.message)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            model.runHealthCheck()
                        } label: {
                            Image(systemName: "stethoscope")
                        }
                        .help("重新检查")
                        .disabled(model.busy)
                    }
                    .padding(.vertical, 4)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 590, idealHeight: 650)
        .onAppear { model.refresh() }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            content()
                .padding(.top, 2)
        }
    }
}

@main
struct ZhiYouApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            Text(model.browserConnected ? "浏览器已连接" : "浏览器未连接")
            Divider()
            Button("打开控制中心") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("重新检查") {
                model.refresh()
            }
            Divider()
            Button("退出智游") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: model.browserConnected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
        }
    }
}
