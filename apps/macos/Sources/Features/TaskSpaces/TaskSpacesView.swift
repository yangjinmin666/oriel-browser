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

            Divider()

            if !model.browserConnected {
                emptyState(
                    icon: "rectangle.slash",
                    title: L10n.text("task_spaces.browser_required"),
                    detail: L10n.text("task_spaces.browser_required_detail")
                )
            } else if model.taskSpacesLoading {
                loadingState()
            } else if model.taskSpaces.isEmpty && !model.taskSpacesLoading {
                emptyState(
                    icon: "square.3.layers.3d",
                    title: L10n.text("task_spaces.empty"),
                    detail: L10n.text("task_spaces.empty_detail")
                )
            } else {
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
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 11)
                                    )
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
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                Text(space.name)
                                    .font(.title3.weight(.semibold))
                                Text(
                                    model.profileState(space.profileId)?.label
                                        ?? space.profileId
                                )
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(
                                        Color(
                                            red: 0.24,
                                            green: 0.52,
                                            blue: 0.96
                                        )
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
                                Text("#\(space.runtimeId)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.text("task_spaces.pages"))
                                    .font(.headline)
                                if space.recentTabTitles.isEmpty {
                                    Text(L10n.text("task_spaces.no_page"))
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(
                                        Array(
                                            space.recentTabTitles.enumerated()
                                        ),
                                        id: \.offset
                                    ) { _, title in
                                        Label(title, systemImage: "globe")
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(22)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.black.opacity(0.06))
                        )
                    }

                    Label(
                        L10n.text("task_spaces.shared_login_note"),
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(26)
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
            if model.taskSpacesLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
