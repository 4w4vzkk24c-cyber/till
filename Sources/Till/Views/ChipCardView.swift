import SwiftUI

/// One chip tile (spec A2): icon, hero digits and a full-width control strip. Chips have no
/// label; the icon is the subject. Fill and outline carry state; the chip's accent
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

        VStack(spacing: 2) {
            ChipIconView(
                iconId: data.iconId, monotone: data.iconMonotone,
                tint: theme.color(p.iconTone, accentHex: data.accentHex))
                .frame(width: 40, height: 40)
                .opacity(p.iconOpacity)

            Text(ChipHero.attributed(p.hero))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.color(p.heroTone, accentHex: data.accentHex))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 28)

            controlStrip(p, theme)
        }
        .padding(.top, 16)
        .padding(.horizontal, 6)
        .padding(.bottom, 14)
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
            shape.fill(theme.tile).overlay(shape.strokeBorder(theme.edge, lineWidth: 1))
        case .dueSoon:
            shape.fill(scheme == .dark ? Color.black.opacity(0.28) : theme.tile)
                .overlay(shape.strokeBorder(theme.amber, lineWidth: 2))
        case .overdue:
            shape.fill(Theme.overdueFill)
        case .paused:
            shape.strokeBorder(theme.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
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
            .foregroundStyle(theme.color(p.controlTone, accentHex: ""))
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(
                p.controlHasFill ? Color.black.opacity(0.28) : Color.clear,
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
