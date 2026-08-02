import SwiftUI

struct ControlCenterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedPage = ProcessInfo.processInfo.environment[
        "ORIEL_OPEN_TASK_SPACES"
    ] == "1" ? 1 : 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 11) {
                    OrielLogoMark(size: 34)
                    Text(Brand.displayName)
                        .font(.custom("Space Grotesk", fixedSize: 24).weight(.semibold))
                }
                Spacer()
                Picker("", selection: $selectedPage) {
                    Text(L10n.text("navigation.control_center")).tag(0)
                    Text(L10n.text("navigation.task_spaces")).tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 236)
                Spacer()
                StatusPill(
                    ready: model.allBrowserProfilesConnected
                        && model.cliInstalled
                        && model.skillInstalled,
                    readyText: L10n.text("control_center.status.ready"),
                    pendingText: L10n.text("control_center.status.setup")
                )
            }
            .padding(.horizontal, 26)
            .frame(height: 72)

            Divider()

            if selectedPage == 0 {
              HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        sectionHeader(
                            L10n.text("control_center.browser.section"),
                            index: "01"
                        )
                        VStack(spacing: 16) {
                            ForEach(model.browserProfiles) { profile in
                                browserProfileCard(profile)
                            }
                        }
                    }
                    .padding(26)
                }
                .frame(minWidth: 390)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sectionHeader(
                            L10n.text("control_center.codex.section"),
                            index: "02"
                        )

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
                                        ? L10n.text("control_center.codex.installed")
                                        : L10n.text("control_center.codex.required"))
                                        .font(.headline)
                                    Text(L10n.text("control_center.codex.detail"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                model.installCodexIntegration()
                            } label: {
                                Label(
                                    model.cliInstalled && model.skillInstalled
                                        ? L10n.text("control_center.codex.reinstall")
                                        : L10n.text("control_center.codex.install"),
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
                            Label(
                                L10n.text("control_center.feature.local"),
                                systemImage: "lock"
                            )
                            Label(
                                L10n.text("control_center.feature.sessions"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            Label(
                                L10n.text("control_center.feature.task_spaces"),
                                systemImage: "square.3.layers.3d"
                            )
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(
                                L10n.text("control_center.health.section"),
                                index: "03"
                            )
                            HealthRow(
                                title: L10n.text("control_center.health.browser"),
                                detail: L10n.format(
                                    "control_center.health.browser.profiles",
                                    model.browserProfiles.filter(\.connected).count,
                                    model.browserProfiles.count
                                ),
                                ready: model.allBrowserProfilesConnected
                            )
                            HealthRow(
                                title: L10n.text("control_center.health.daemon"),
                                detail: model.daemonRunning
                                    ? L10n.format("control_center.health.daemon.running", model.daemonClientCount)
                                    : L10n.text("control_center.health.daemon.stopped"),
                                ready: true
                            )
                            HealthRow(
                                title: L10n.text("control_center.health.configuration"),
                                detail: model.configurationValid
                                    ? L10n.text("control_center.health.configuration.ready")
                                    : L10n.text("control_center.health.configuration.needs_repair"),
                                ready: model.configurationValid
                            )

                            Button {
                                model.repairConnection()
                            } label: {
                                Label(
                                    L10n.text("control_center.health.repair"),
                                    systemImage: "wrench.and.screwdriver"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(model.busy)

                            Text(L10n.text("control_center.health.repair_detail"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(Brand.releaseLabel)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button {
                                model.runHealthCheck()
                            } label: {
                                Image(systemName: "stethoscope")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.text("control_center.diagnostics"))
                            .disabled(model.busy)
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 310)
              }
            } else {
                TaskSpacesView()
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
        .frame(minWidth: 760, idealWidth: 900, minHeight: 620, idealHeight: 720)
        .background(Color(red: 0.965, green: 0.965, blue: 0.972))
        .foregroundStyle(Color.black)
        .tint(Color.black)
        .preferredColorScheme(.light)
        .onAppear {
            if ProcessInfo.processInfo.environment[
                "ORIEL_OPEN_TASK_SPACES"
            ] == "1" {
                selectedPage = 1
            }
            model.refresh()
        }
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

    private func browserProfileCard(
        _ profile: BrowserProfileState
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.label)
                        .font(.headline)
                    Text(L10n.format(
                        "control_center.browser.profile_endpoint",
                        profile.port
                    ))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    ready: profile.connected,
                    readyText: L10n.text(
                        "control_center.browser.connected"
                    ),
                    pendingText: L10n.text(
                        "control_center.browser.disconnected"
                    )
                )
            }

            VStack(spacing: 3) {
                ForEach(model.browsers) { browser in
                    BrowserRow(
                        browser: browser,
                        selected: profile.selectedBrowserId == browser.id,
                        selectionLocked: profile.connected,
                        action: {
                            model.select(
                                browser,
                                profileId: profile.id
                            )
                        }
                    )
                }
            }

            HStack(spacing: 12) {
                Text(
                    profile.connected
                        ? L10n.text(
                            "control_center.browser.connected_detail"
                        )
                        : L10n.text(
                            "control_center.browser.disconnected_detail"
                        )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if profile.connected {
                    Button {
                        model.stopBrowser(profileId: profile.id)
                    } label: {
                        Label(
                            L10n.text("control_center.browser.stop"),
                            systemImage: "stop.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.busy)
                } else {
                    Button {
                        model.startBrowser(profileId: profile.id)
                    } label: {
                        Label(
                            L10n.text("control_center.browser.start"),
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                    .foregroundStyle(.white)
                    .disabled(model.busy)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.07))
        )
    }
}
