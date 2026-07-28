import AppKit
import SwiftUI

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
            .accessibilityLabel(
                ready
                    ? L10n.text("accessibility.status.ready")
                    : L10n.text("accessibility.status.not_ready")
            )
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
                    Text(
                        browser.installed
                            ? L10n.text("browser.detected")
                            : L10n.text("browser.not_installed")
                    )
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

struct HealthRow: View {
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(ready: ready)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ready ? L10n.text("health.ready") : L10n.text("health.attention"))
                .font(.caption.weight(.medium))
                .foregroundStyle(ready ? Color(red: 0.24, green: 0.52, blue: 0.96) : Color(red: 0.93, green: 0.27, blue: 0.31))
        }
    }
}
