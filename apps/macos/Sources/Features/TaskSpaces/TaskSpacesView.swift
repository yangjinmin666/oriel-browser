import SwiftUI

struct TaskSpacesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSpaceId: String?

    private var selectedSpace: TaskSpaceSummary? {
        if let selectedSpaceId,
           let selected = model.taskSpaces.first(
               where: { $0.id == selectedSpaceId }
           ) {
            return selected
        }
        return model.taskSpaces.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !model.browserConnected {
                emptyState(
                    icon: "rectangle.slash",
                    title: L10n.text("task_spaces.browser_required"),
                    detail: L10n.text("task_spaces.browser_required_detail")
                )
            } else if model.taskSpacesLoading && model.taskSpaces.isEmpty {
                loadingState()
            } else if model.taskSpaces.isEmpty {
                if model.taskAuditEvents.isEmpty {
                    emptyState(
                        icon: "square.3.layers.3d",
                        title: L10n.text("task_spaces.empty"),
                        detail: L10n.text("task_spaces.empty_detail")
                    )
                } else {
                    auditOnlyState()
                }
            } else {
                taskSpaceContent
            }
        }
        .onAppear {
            model.refreshTaskSpaces()
        }
        .onChange(of: model.taskSpaces) { spaces in
            if !spaces.contains(where: { $0.id == selectedSpaceId }) {
                selectedSpaceId = spaces.first?.id
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("task_spaces.title"))
                    .font(.title2.weight(.semibold))
                Text(L10n.text("task_spaces.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refreshTaskSpaces()
            } label: {
                Label(
                    L10n.text("task_spaces.refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(!model.browserConnected || model.taskSpacesLoading)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }

    private var taskSpaceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.taskSpaces) { space in
                            Button {
                                selectedSpaceId = space.id
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(
                                            space.isAgentOwned
                                                ? Color(
                                                    red: 0.43,
                                                    green: 0.31,
                                                    blue: 0.96
                                                )
                                                : Color.orange
                                        )
                                        .frame(width: 8, height: 8)
                                    Text(space.name)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(
                                    selectedSpace?.id == space.id
                                        ? Color.white
                                        : Color.black.opacity(0.035)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .stroke(
                                            selectedSpace?.id == space.id
                                                ? Color.black.opacity(0.18)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let space = selectedSpace {
                    taskCard(space)
                }

                Label(
                    L10n.text("task_spaces.shared_login_note"),
                    systemImage: "person.2.badge.key"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(26)
        }
    }

    private func taskCard(_ space: TaskSpaceSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(space.name)
                        .font(.title3.weight(.semibold))
                    Text(
                        model.profileState(space.profileId)?.label
                            ?? space.profileId
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        Color(red: 0.24, green: 0.52, blue: 0.96)
                    )
                    Text(
                        space.isAgentOwned
                            ? L10n.text("task_spaces.agent_control")
                            : L10n.text("task_spaces.user_control")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(lifecycleTitle(space.lifecycleStatus))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(space.lifecycleStatus).opacity(0.13))
                        .foregroundStyle(statusColor(space.lifecycleStatus))
                        .clipShape(Capsule())
                    Text("#\(space.runtimeId)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.text("task_spaces.authorization"))
                    .font(.headline)
                HStack(spacing: 10) {
                    Menu {
                        Button(L10n.text("task_spaces.policy.read_only")) {
                            model.setTaskPolicy("read-only", for: space)
                        }
                        Button(L10n.text("task_spaces.policy.draft")) {
                            model.setTaskPolicy("draft", for: space)
                        }
                        Button(L10n.text("task_spaces.policy.requires_approval")) {
                            model.setTaskPolicy("requires-approval", for: space)
                        }
                    } label: {
                        Label(
                            policyTitle(space.executionPolicyValue),
                            systemImage: "lock.shield"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.taskSpacesLoading)

                    if space.executionPolicyValue == "requires-approval" {
                        Button {
                            model.approveTaskAction(space)
                        } label: {
                            Label(
                                space.lifecycle?.approvalAvailable == true
                                    ? L10n.text("task_spaces.approval_ready")
                                    : L10n.text("task_spaces.approve_next"),
                                systemImage: "checkmark.shield"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            model.taskSpacesLoading
                                || space.lifecycle?.approvalAvailable == true
                        )
                    }
                }
                Text(policyDetail(space.executionPolicyValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.text("task_spaces.lifecycle"))
                    .font(.headline)
                Text(lifecycleDetail(space))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if space.isAgentOwned {
                        Button {
                            model.handOffTaskSpace(space)
                        } label: {
                            Label(
                                L10n.text("task_spaces.hand_off"),
                                systemImage: "hand.raised"
                            )
                        }
                    } else {
                        Button {
                            model.resumeTaskSpace(space)
                        } label: {
                            Label(
                                L10n.text("task_spaces.resume_agent"),
                                systemImage: "play.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if space.requiresRecovery {
                        Button {
                            model.recoverTaskSpace(space)
                        } label: {
                            Label(
                                L10n.text("task_spaces.recover"),
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.taskSpacesLoading)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("task_spaces.pages"))
                    .font(.headline)
                if space.recentTabTitles.isEmpty {
                    Text(L10n.text("task_spaces.no_page"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(space.recentTabTitles.enumerated()),
                        id: \.offset
                    ) { _, title in
                        Label(title, systemImage: "globe")
                            .lineLimit(2)
                    }
                }
            }

            auditHistory(events: auditEvents(for: space))
        }
        .padding(22)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.06))
        )
    }

    private func auditOnlyState() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(
                    L10n.text("task_spaces.audit_history"),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.title3.weight(.semibold))
                Text(L10n.text("task_spaces.audit_history_detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                auditHistory(events: model.taskAuditEvents)
            }
            .padding(26)
        }
    }

    private func auditHistory(events: [TaskAuditEvent]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.text("task_spaces.audit"))
                    .font(.headline)
                Spacer()
                Text(L10n.format("task_spaces.audit_count", events.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if events.isEmpty {
                Text(L10n.text("task_spaces.audit_empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.prefix(8))) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(auditTitle(event))
                            .font(.caption.weight(.medium))
                        HStack(spacing: 6) {
                            Text(event.at)
                            if let code = event.code {
                                Text(code)
                            }
                            if let recovery = event.safeRecovery {
                                Text(recovery)
                            }
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func auditEvents(for space: TaskSpaceSummary) -> [TaskAuditEvent] {
        model.taskAuditEvents.filter {
            $0.profileId == space.profileId && $0.runtimeId == space.runtimeId
        }
    }

    private func policyTitle(_ policy: String) -> String {
        switch policy {
        case "read-only":
            return L10n.text("task_spaces.policy.read_only")
        case "draft":
            return L10n.text("task_spaces.policy.draft")
        default:
            return L10n.text("task_spaces.policy.requires_approval")
        }
    }

    private func policyDetail(_ policy: String) -> String {
        switch policy {
        case "read-only":
            return L10n.text("task_spaces.policy.read_only_detail")
        case "draft":
            return L10n.text("task_spaces.policy.draft_detail")
        default:
            return L10n.text("task_spaces.policy.requires_approval_detail")
        }
    }

    private func lifecycleTitle(_ status: String) -> String {
        switch status {
        case "handed-off":
            return L10n.text("task_spaces.status.handed_off")
        case "blocked":
            return L10n.text("task_spaces.status.blocked")
        case "failed":
            return L10n.text("task_spaces.status.failed")
        case "completed":
            return L10n.text("task_spaces.status.completed")
        case "stopped":
            return L10n.text("task_spaces.status.stopped")
        default:
            return L10n.text("task_spaces.status.running")
        }
    }

    private func lifecycleDetail(_ space: TaskSpaceSummary) -> String {
        if let failure = space.lifecycle?.lastFailure {
            return L10n.format(
                "task_spaces.failure_detail",
                failure.code,
                failure.safeRecovery
            )
        }
        if space.lifecycle?.approvalAvailable == true {
            return L10n.text("task_spaces.approval_detail")
        }
        return L10n.format(
            "task_spaces.stage_detail",
            space.lifecycle?.stage ?? "running"
        )
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "handed-off", "blocked":
            return .orange
        case "failed":
            return .red
        case "completed", "stopped":
            return .secondary
        default:
            return Color(red: 0.31, green: 0.25, blue: 0.9)
        }
    }

    private func auditTitle(_ event: TaskAuditEvent) -> String {
        switch event.type {
        case "task.created":
            return L10n.text("task_spaces.audit.task_created")
        case "policy.changed":
            return L10n.text("task_spaces.audit.policy_changed")
        case "approval.granted":
            return L10n.text("task_spaces.audit.approval_granted")
        case "action.allowed":
            return L10n.text("task_spaces.audit.action_allowed")
        case "action.blocked":
            return L10n.text("task_spaces.audit.action_blocked")
        case "browser.prepared":
            return L10n.text("task_spaces.audit.browser_prepared")
        case "control.handed-off", "agent.hard-stopped":
            return L10n.text("task_spaces.audit.handed_off")
        case "control.resumed":
            return L10n.text("task_spaces.audit.resumed")
        case "recovery.requested":
            return L10n.text("task_spaces.audit.recovery")
        case "task.failed":
            return L10n.text("task_spaces.audit.failed")
        case "task.completed":
            return L10n.text("task_spaces.audit.completed")
        case "task.closed":
            return L10n.text("task_spaces.audit.closed")
        default:
            return L10n.text("task_spaces.audit.recorded")
        }
    }

    private func loadingState() -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(L10n.text("task_spaces.loading"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func emptyState(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
