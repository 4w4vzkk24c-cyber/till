import SwiftUI

/// One chip card, per design §4: icon, caption label (gray), hero time (rounded,
/// monospaced digits), minimal pause control. Static: no animation, state changes swap.
struct ChipCardView: View {
    let data: ChipViewData
    let now: Date
    let onPauseResume: () -> Void
    let onDone: () -> Void
    let onEdit: () -> Void

    private static let cardFill = Color(red: 0.17, green: 0.16, blue: 0.15)

    var body: some View {
        let state = data.state(at: now)
        let accent = Color(hex: data.accentHex)

        VStack(spacing: 6) {
            ChipIconView(
                iconId: data.iconId, monotone: data.iconMonotone,
                tint: state == .paused ? accent.opacity(0.4) : accent)
                .frame(width: 44, height: 44)
                .padding(.top, 14)

            if let label = data.label, !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(data.heroText(at: now))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(heroColor(state, accent: accent))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            control(state)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Self.cardFill, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button("Edit", action: onEdit)
            if state == .paused {
                Button("Resume", action: onPauseResume)
            } else if state != .overdue {
                Button("Pause", action: onPauseResume)
            }
            Button("Done", action: onDone)
        }
        // One accessible element with state-bearing text and named actions (A1.1 item 5).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.accessibilityLabel(at: now))
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Done", onDone)
        .accessibilityAction(named: state == .paused ? "Resume" : "Pause") {
            if state != .overdue { onPauseResume() }
        }
    }

    @ViewBuilder
    private func control(_ state: ChipState) -> some View {
        if state == .overdue {
            // Done is the only exit from Overdue (settled #3), so it is visible, not buried.
            Button(action: onDone) {
                Label("Done", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else {
            Button(action: onPauseResume) {
                Image(systemName: state == .paused ? "play.fill" : "pause.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(state == .paused ? "Resume" : "Pause")
        }
    }

    private func heroColor(_ state: ChipState, accent: Color) -> Color {
        switch state {
        case .clean: return Color.white.opacity(0.9)
        case .approaching: return accent
        case .overdue: return .red
        case .paused: return Color.white.opacity(0.4)
        }
    }
}
