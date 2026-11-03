import SwiftUI

/// One chip tile (spec A2): icon, hero digits, a full-width control strip, and the label
/// under it. Fill and outline carry state; the chip's accent
/// colours its icon only. Static: no animation, state changes swap.
struct ChipCardView: View {
    let data: ChipViewData
    let now: Date
    let onPauseResume: () -> Void
    let onDone: () -> Void
    let onEdit: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let state = data.state(at: now)
        let theme = Theme(scheme, contrast)
        let p = ChipPresentation(state: state, heroText: data.heroText(at: now))
        let overdue = p.surface == .overdue

        VStack(spacing: 2) {
            ChipIconView(
                iconId: data.iconId, monotone: data.iconMonotone,
                tint: overdue ? .white : theme.accent(data.accentHex))
                .frame(width: 40, height: 40)
                .opacity(p.surface == .paused ? 0.5 : 1)

            Text(p.hero)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(heroColor(p.surface, theme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 28)

            controlStrip(p, theme)

            // The label sits under the control. Its slot is always reserved so an
            // unlabeled chip keeps the tile height.
            Text(data.label ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(labelColor(p.surface, theme))
                .lineLimit(1)
                .frame(height: 14)
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .frame(height: ChipGridLayout.tileHeight)
        .background { surface(p.surface, theme) }
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

    // MARK: - Surface

    @ViewBuilder
    private func surface(_ surface: ChipPresentation.Surface, _ theme: Theme) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        switch surface {
        case .neutral:
            shape.fill(theme.tile).overlay(shape.strokeBorder(theme.hairline, lineWidth: 0.5))
        case .dueSoon:
            shape.fill(scheme == .dark ? Color.black.opacity(0.28) : theme.tile)
                .overlay(shape.strokeBorder(theme.amber, lineWidth: 2))
        case .overdue:
            shape.fill(Theme.overdueFill)
        case .paused:
            shape.strokeBorder(theme.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }

    private func labelColor(_ s: ChipPresentation.Surface, _ theme: Theme) -> Color {
        switch s {
        case .overdue: return .white
        case .paused: return theme.ink3
        default: return theme.ink2
        }
    }

    private func heroColor(_ s: ChipPresentation.Surface, _ theme: Theme) -> Color {
        switch s {
        case .neutral: return theme.ink
        case .dueSoon: return theme.amber
        case .overdue: return .white
        case .paused: return theme.ink2
        }
    }

    // MARK: - Control

    /// Pause / resume, or Done on an overdue tile (Done is the only exit from Overdue,
    /// settled #3, so it replaces pause and is visible, not buried). A real Button, so it
    /// is keyboard-focusable; the whole strip is the hit target.
    private func controlStrip(_ p: ChipPresentation, _ theme: Theme) -> some View {
        Button(action: p.control == .done ? onDone : onPauseResume) {
            Group {
                switch p.control {
                case .pause: Image(systemName: "pause.fill").font(.system(size: 13))
                case .resume: Image(systemName: "play.fill").font(.system(size: 13))
                case .done: Text("Done").font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(p.control == .done ? Color.white : theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(
                p.control == .done ? Color.black.opacity(0.28) : Color.clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(p.control))
    }

    private func helpText(_ control: ChipPresentation.Control) -> String {
        switch control {
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .done: return "Mark done"
        }
    }
}
