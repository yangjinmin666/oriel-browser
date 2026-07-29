import Foundation

extension AppModel {
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
                    userInfo: [
                        NSLocalizedDescriptionKey: L10n.text(
                            "error.codex.runtime_incomplete"
                        )
                    ]
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
            let compatibilitySkillSource = resources
                .appendingPathComponent("Skill", isDirectory: true)
                .appendingPathComponent(
                    Brand.compatibilitySkillName,
                    isDirectory: true
                )
            let skillSources = [
                Brand.skillName: skillSource,
                Brand.compatibilitySkillName: compatibilitySkillSource,
            ]
            guard skillSources.values.allSatisfy({
                FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent("SKILL.md").path
                )
            }) else {
                throw NSError(
                    domain: "Oriel",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: L10n.text(
                            "error.codex.runtime_incomplete"
                        )
                    ]
                )
            }

            let home = FileManager.default.homeDirectoryForCurrentUser
            for relativeRoot in Brand.agentSkillRootRelativePaths {
                let skillRoot = home.appendingPathComponent(
                    relativeRoot,
                    isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: skillRoot,
                    withIntermediateDirectories: true
                )

                // Oriel's skill replaces the old agent-facing ego-browser
                // contract. Its compatibility entry uses only current helpers.
                for skillName in Brand.installedSkillNames
                    + Brand.conflictingSkillNames {
                    let destination = skillRoot.appendingPathComponent(
                        skillName,
                        isDirectory: true
                    )
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                }

                for skillName in Brand.installedSkillNames {
                    guard let source = skillSources[skillName] else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    try FileManager.default.copyItem(
                        at: source,
                        to: skillRoot.appendingPathComponent(
                            skillName,
                            isDirectory: true
                        )
                    )
                }
            }
            try saveAllConfigurations()
            cliInstalled = true
            skillInstalled = true
            message = L10n.text("message.codex.installed")
        } catch {
            lastError = error.localizedDescription
        }
        busy = false
    }
}
