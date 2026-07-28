import AppKit
import Foundation
import SwiftUI

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
                        domain: "Oriel",
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
                    domain: "Oriel",
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
            let entry = runtime.appendingPathComponent("oriel.mjs")
            guard FileManager.default.isExecutableFile(atPath: node.path),
                  FileManager.default.fileExists(atPath: entry.path) else {
                throw NSError(
                    domain: "Oriel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "应用内置运行时不完整，请重新安装 Oriel。"]
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
            for commandName in [Brand.cliName] + Brand.legacyCLINames {
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
            if FileManager.default.fileExists(atPath: skillDestination.path) {
                try FileManager.default.removeItem(at: skillDestination)
            }
            for legacySkillName in Brand.legacySkillNames {
                let legacySkillDestination = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(
                        ".codex/skills/\(legacySkillName)",
                        isDirectory: true
                    )
                if FileManager.default.fileExists(atPath: legacySkillDestination.path) {
                    try FileManager.default.removeItem(at: legacySkillDestination)
                }
            }
            try FileManager.default.createDirectory(
                at: skillDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: skillSource, to: skillDestination)
            try saveConfiguration()
            cliInstalled = true
            skillInstalled = true
            message = "Oriel 集成已安装，后台会在首次任务时自动启动。重新打开 Codex 后即可使用。"
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
                message = "使用前检查通过，持久后台会在首次任务时自动启动。"
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
                domain: "Oriel",
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
            .fill(
                ready
                    ? Color(red: 0.24, green: 0.52, blue: 0.96)
                    : Color(red: 0.93, green: 0.27, blue: 0.31)
            )
            .frame(width: 8, height: 8)
            .accessibilityLabel(ready ? "已就绪" : "未就绪")
    }
}

struct OrielLogoMark: View {
    let size: CGFloat

    private var image: NSImage {
        guard let url = Bundle.main.url(forResource: "OrielLogo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        return image
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.11))
            .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
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
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color.black.opacity(0.08) : Color.black.opacity(0.035))
                    )
                    .foregroundStyle(browser.installed ? Color.black : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.name)
                        .font(.callout.weight(.medium))
                    Text(browser.installed ? "已检测到" : "未安装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.24, green: 0.52, blue: 0.96))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.black.opacity(0.045) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!browser.installed || (selectionLocked && !selected))
    }
}

struct StatusPill: View {
    let ready: Bool
    let readyText: String
    let pendingText: String

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(ready: ready)
            Text(ready ? readyText : pendingText)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            Capsule()
                .fill(
                    ready
                        ? Color(red: 0.24, green: 0.52, blue: 0.96).opacity(0.16)
                        : Color(red: 0.93, green: 0.27, blue: 0.31).opacity(0.16)
                )
        )
    }
}

struct ControlCenterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 11) {
                    OrielLogoMark(size: 34)
                    Text(Brand.displayName)
                        .font(.custom("Space Grotesk", fixedSize: 24).weight(.semibold))
                }
                Spacer()
                StatusPill(
                    ready: model.browserConnected && model.cliInstalled && model.skillInstalled,
                    readyText: "Ready",
                    pendingText: "Setup"
                )
            }
            .padding(.horizontal, 26)
            .frame(height: 72)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        sectionHeader("Browser", index: "01")
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

                        Divider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.browserConnected ? "Connected" : "Not connected")
                                    .font(.headline)
                                Text(model.browserConnected ? "本机浏览器连接正在运行" : "选择浏览器后启动连接")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.browserConnected {
                                Button {
                                    model.stopBrowser()
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.busy)
                            } else {
                                Button {
                                    model.startBrowser()
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.black)
                                .foregroundStyle(.white)
                                .disabled(model.busy)
                            }
                        }
                    }
                    .padding(26)
                }
                .frame(minWidth: 390)

                Divider()

                VStack(alignment: .leading, spacing: 24) {
                    sectionHeader("Codex", index: "02")

                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: model.cliInstalled && model.skillInstalled
                                ? "checkmark.circle.fill"
                                : "arrow.down.circle")
                                .font(.system(size: 21))
                                .foregroundStyle(
                                    model.cliInstalled && model.skillInstalled
                                        ? Color(red: 0.24, green: 0.52, blue: 0.96)
                                        : Color(red: 0.93, green: 0.27, blue: 0.31)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.cliInstalled && model.skillInstalled
                                    ? "Integration installed"
                                    : "Integration required")
                                    .font(.headline)
                                Text("CLI + browser skill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            model.installCodexIntegration()
                        } label: {
                            Label(
                                model.cliInstalled && model.skillInstalled ? "Reinstall" : "Install",
                                systemImage: "square.and.arrow.down"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                        .foregroundStyle(.white)
                        .controlSize(.large)
                        .disabled(model.busy)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Local only", systemImage: "lock")
                        Label("Persistent sessions", systemImage: "arrow.triangle.2.circlepath")
                        Label("Private task spaces", systemImage: "square.3.layers.3d")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Spacer()

                    HStack {
                        Text("v0.2.0 alpha")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            model.runHealthCheck()
                        } label: {
                            Image(systemName: "stethoscope")
                        }
                        .buttonStyle(.borderless)
                        .help("Run diagnostics")
                        .disabled(model.busy)
                    }
                }
                .padding(26)
                .frame(width: 310)
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: model.lastError == nil ? "info.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(
                        model.lastError == nil
                            ? Color(red: 0.24, green: 0.52, blue: 0.96)
                            : Color(red: 0.93, green: 0.27, blue: 0.31)
                    )
                Text(model.lastError ?? model.message)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                if model.busy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 26)
            .frame(minHeight: 58)
            .background(Color.black.opacity(0.025))
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 590)
        .background(Color(red: 0.965, green: 0.965, blue: 0.972))
        .foregroundStyle(Color.black)
        .tint(Color.black)
        .preferredColorScheme(.light)
        .onAppear { model.refresh() }
    }

    private func sectionHeader(_ title: String, index: String) -> some View {
        HStack(spacing: 10) {
            Text(index)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.48))
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }
}

struct GridScanField: View {
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let time = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                    let background = Path(CGRect(origin: .zero, size: size))
                    context.fill(
                        background,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(red: 0.986, green: 0.986, blue: 0.990),
                                Color(red: 0.944, green: 0.944, blue: 0.952),
                                Color(red: 0.978, green: 0.978, blue: 0.982)
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: size.height)
                        )
                    )

                    let vanishingPoint = CGPoint(
                        x: size.width * (0.5 + (pointer.x - 0.5) * 0.13),
                        y: size.height * (0.46 + (pointer.y - 0.5) * 0.09)
                    )
                    let outer = [
                        CGPoint(x: -size.width * 0.20, y: -size.height * 0.18),
                        CGPoint(x: size.width * 1.20, y: -size.height * 0.18),
                        CGPoint(x: size.width * 1.20, y: size.height * 1.18),
                        CGPoint(x: -size.width * 0.20, y: size.height * 1.18)
                    ]

                    drawRays(
                        context: &context,
                        size: size,
                        vanishingPoint: vanishingPoint,
                        outer: outer,
                        time: time
                    )

                    for index in 1...22 {
                        let normalized = CGFloat(index) / 22
                        let depth = pow(normalized, 1.72)
                        let jitter = sin(time * 1.65 + CGFloat(index) * 2.31) * 0.0018
                        let ring = ringPath(
                            vanishingPoint: vanishingPoint,
                            outer: outer,
                            amount: min(1, max(0, depth + jitter))
                        )
                        context.stroke(
                            ring,
                            with: .color(Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.18)),
                            lineWidth: 0.85
                        )
                    }

                    drawScan(
                        context: &context,
                        vanishingPoint: vanishingPoint,
                        outer: outer,
                        time: time
                    )

                    for index in 0..<54 {
                        let seed = CGFloat(index)
                        let x = fractional(sin(seed * 12.9898) * 43_758.5453) * size.width
                        let y = fractional(sin((seed + 19) * 78.233) * 12_345.678) * size.height
                        let radius = 0.35 + CGFloat(index % 3) * 0.25
                        let grain = Path(
                            ellipseIn: CGRect(
                                x: x - radius,
                                y: y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                        )
                        context.fill(
                            grain,
                            with: .color(Color.black.opacity(0.025 + Double(index % 4) * 0.008))
                        )
                    }
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    pointer = CGPoint(
                        x: min(1, max(0, location.x / max(1, proxy.size.width))),
                        y: min(1, max(0, location.y / max(1, proxy.size.height)))
                    )
                case .ended:
                    withAnimation(.easeOut(duration: 0.28)) {
                        pointer = CGPoint(x: 0.5, y: 0.5)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawRays(
        context: inout GraphicsContext,
        size: CGSize,
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        time: CGFloat
    ) {
        let segments = 9
        for edge in 0..<4 {
            let start = outer[edge]
            let end = outer[(edge + 1) % 4]
            for index in 0...segments {
                let amount = CGFloat(index) / CGFloat(segments)
                var endpoint = CGPoint(
                    x: start.x + (end.x - start.x) * amount,
                    y: start.y + (end.y - start.y) * amount
                )
                let jitter = sin(time * 1.8 + CGFloat(edge * 13 + index) * 1.41) * 1.1
                if edge % 2 == 0 {
                    endpoint.x += jitter
                } else {
                    endpoint.y += jitter
                }
                var ray = Path()
                ray.move(to: vanishingPoint)
                ray.addLine(to: endpoint)
                context.stroke(
                    ray,
                    with: .color(Color(red: 0.18, green: 0.18, blue: 0.20).opacity(0.16)),
                    lineWidth: 0.8
                )
            }
        }
    }

    private func drawScan(
        context: inout GraphicsContext,
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        time: CGFloat
    ) {
        let duration: CGFloat = 2.0
        let delay: CGFloat = 1.1
        let cycle = duration + delay
        let cycleIndex = Int(floor(time / cycle))
        let cycleTime = time.truncatingRemainder(dividingBy: cycle)
        guard cycleTime >= delay else { return }

        var phase = min(1, max(0, (cycleTime - delay) / duration))
        if cycleIndex % 2 == 1 {
            phase = 1 - phase
        }
        let eased = phase * phase * (3 - 2 * phase)
        let depth = 0.07 + eased * 0.91
        let scan = ringPath(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: depth
        )

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.stroke(
                scan,
                with: .color(Color.black.opacity(0.12)),
                lineWidth: 18
            )
        }
        context.stroke(
            scan,
            with: .color(Color.black.opacity(0.34)),
            lineWidth: 1.4
        )

        let inner = ringPoints(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: max(0.02, depth - 0.025)
        )
        let outside = ringPoints(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: min(1, depth + 0.025)
        )
        var band = Path()
        band.move(to: inner[0])
        inner.dropFirst().forEach { band.addLine(to: $0) }
        outside.reversed().forEach { band.addLine(to: $0) }
        band.closeSubpath()
        context.fill(
            band,
            with: .color(Color.black.opacity(0.035))
        )
    }

    private func ringPath(
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        amount: CGFloat
    ) -> Path {
        let points = ringPoints(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: amount
        )
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func ringPoints(
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        amount: CGFloat
    ) -> [CGPoint] {
        outer.map { point in
            CGPoint(
                x: vanishingPoint.x + (point.x - vanishingPoint.x) * amount,
                y: vanishingPoint.y + (point.y - vanishingPoint.y) * amount
            )
        }
    }

    private func fractional(_ value: CGFloat) -> CGFloat {
        value - floor(value)
    }
}

struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        ZStack {
            GridScanField()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome to")
                            .font(.system(size: 34, weight: .regular))
                        Text("Oriel")
                            .font(.custom("Space Grotesk", fixedSize: 50).weight(.semibold))
                    }
                    Spacer()
                    OrielLogoMark(size: 62)
                }

                Spacer()

                Text("A shared view for\nyou and your AI.")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.black.opacity(0.88))

                Button(action: continueAction) {
                    HStack {
                        Text("Get started")
                            .font(.system(size: 34, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 34))
                    }
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
            .padding(42)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 700, idealHeight: 760)
        .preferredColorScheme(.light)
    }
}

@main
struct OrielApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ControlCenterView()
                        .environmentObject(model)
                } else {
                    WelcomeView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            hasCompletedOnboarding = true
                        }
                    }
                }
            }
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
            Button("退出 Oriel") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: model.browserConnected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
        }
    }
}
