import AppKit
import Observation
import SwiftUI

/// Search state for the inline icon picker. Results from a superseded or dismissed search
/// are dropped via a generation counter.
@MainActor
@Observable
final class IconPickerModel {
    enum Status: Equatable {
        case idle
        case searching
        case empty
        case failed(String)
    }

    /// How many results the picker draws (two rows of six). The service may return up to
    /// 64; showing a page keeps the picker a fixed, scroll-free height.
    static let visibleLimit = 12

    var query = ""
    private(set) var results: [IconSearchResult] = []
    private(set) var status: Status = .idle
    /// Trimmed text of the most recent search, for the no-results message.
    private(set) var lastQuery = ""
    /// The result whose license and tint note the picker shows (hover, or the first result).
    var highlighted: IconSearchResult?

    var visibleResults: [IconSearchResult] { Array(results.prefix(Self.visibleLimit)) }

    @ObservationIgnored let provider: any IconFetching
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(provider: any IconFetching) {
        self.provider = provider
    }

    func startSearch() {
        searchTask?.cancel()
        searchTask = Task { await self.search() }
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        generation += 1
        let gen = generation
        lastQuery = trimmed
        guard !trimmed.isEmpty else {
            results = []
            highlighted = nil
            status = .failed(IconError.invalidQuery.hint)
            return
        }
        status = .searching
        do {
            let found = try await provider.search(query: trimmed, prefix: nil, limit: 64)
            guard gen == generation else { return }
            results = found
            highlighted = found.first
            status = found.isEmpty ? .empty : .idle
        } catch is CancellationError {
            return
        } catch {
            guard gen == generation else { return }
            results = []
            highlighted = nil
            status = .failed((error as? IconError)?.hint ?? IconError.network.hint)
        }
    }

    /// Popover dismissed.
    func cancel() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        if status == .searching { status = .idle }
    }

    /// The one line of text under the search field for a state, or nil when there is none.
    /// Never blank after a search: an empty result says what to try.
    static func statusText(for status: Status, query: String) -> String? {
        switch status {
        case .idle: return nil
        case .searching: return "Searching…"
        case .empty: return "No icons match “\(query)”. Try a simpler word, such as coffee or bell."
        case .failed(let hint): return hint
        }
    }

    /// Pick-time disclosure (design §5 step 1): collection, license, and the conditional
    /// tint. The collection-level palette flag is a hint; the fetched asset wins at creation.
    static func disclosure(for result: IconSearchResult) -> String {
        var parts: [String] = []
        if let name = result.collectionName { parts.append(name) }
        if let license = result.licenseTitle { parts.append(license) }
        switch result.paletteHint {
        case .some(true): parts.append("multicolor — keeps its own colors")
        case .some(false): parts.append("single color — takes the chip’s color")
        case .none: parts.append("color is detected when added")
        }
        return parts.joined(separator: " · ")
    }

    static func disclosure(for choice: IconChoice) -> String {
        if choice.isBuiltIn { return "Built-in icon" }
        var parts: [String] = []
        if let name = choice.collectionName { parts.append(name) }
        if let license = choice.licenseTitle { parts.append(license) }
        parts.append(choice.monotone ? "single color — takes the chip’s color" : "multicolor — keeps its own colors")
        return parts.joined(separator: " · ")
    }
}

/// Inline icon picker (spec A2): search field, a fixed page of results, the highlighted
/// result's license line, and the built-in row, which always works offline.
struct IconPickerView: View {
    @Bindable var model: IconPickerModel
    let creation: CreationFlow

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        let theme = Theme(scheme, contrast)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField("Search icons, e.g. coffee", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, Theme.Space.m)
                .frame(height: 32)
                .background(Color.black.opacity(0.2), in: Capsule())
                .onSubmit { model.startSearch() }
                .accessibilityLabel("Search icons")

            statusView(theme)

            if !model.visibleResults.isEmpty {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.visibleResults) { result in
                        Button {
                            creation.selectIcon(
                                IconChoice(
                                    id: result.id, monotone: !(result.paletteHint ?? false),
                                    collectionName: result.collectionName,
                                    licenseTitle: result.licenseTitle))
                        } label: {
                            IconPreviewCell(
                                provider: model.provider, result: result, theme: theme,
                                highlighted: model.highlighted?.id == result.id)
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in if inside { model.highlighted = result } }
                        .help(IconPickerModel.disclosure(for: result))
                        .accessibilityLabel(result.id)
                        .accessibilityHint(IconPickerModel.disclosure(for: result))
                    }
                }
                if let highlighted = model.highlighted {
                    Text(IconPickerModel.disclosure(for: highlighted))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink2)
                }
            }

            builtInRow(theme)
        }
        .padding(8)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            shape.fill(theme.tile).overlay(shape.strokeBorder(theme.edge, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func statusView(_ theme: Theme) -> some View {
        if let text = IconPickerModel.statusText(for: model.status, query: model.lastQuery) {
            if case .failed = model.status {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Theme.overdueFill.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            } else {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink2)
            }
        }
    }

    /// Built-in set: always available, including when the service is unreachable.
    private func builtInRow(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Rectangle().fill(theme.hairline).frame(height: 0.5)
            HStack(spacing: 6) {
                ForEach(FallbackIcons.all, id: \.self) { id in
                    Button {
                        creation.selectIcon(FallbackIcons.choice(for: id))
                    } label: {
                        ChipIconView(iconId: id, monotone: FallbackIcons.choice(for: id).monotone, tint: theme.ink)
                            .frame(width: 16, height: 16)
                            .frame(width: 26, height: 26)
                            .background(
                                theme.tile,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Built-in icon \(FallbackIcons.displayName(for: id))")
                }
            }
        }
    }
}

/// One search result. Fetching the preview also warms the disk cache, so picking it and
/// creating the chip later is a cache hit with no further network call.
struct IconPreviewCell: View {
    let provider: any IconFetching
    let result: IconSearchResult
    let theme: Theme
    let highlighted: Bool

    @State private var image: NSImage?
    @State private var monotone = true
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                if monotone {
                    Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                        .foregroundStyle(theme.ink)
                } else {
                    Image(nsImage: image).renderingMode(.original).resizable().scaledToFit()
                }
            } else if failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.ink3)
            } else {
                Color.clear
            }
        }
        .frame(width: 24, height: 24)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            theme.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(theme.ink, lineWidth: 2)
            }
        }
        .task(id: result.id) {
            do {
                let asset = try await provider.fetch(id: result.id)
                image = NSImage(contentsOf: asset.fileURL)
                monotone = asset.monotone
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
        }
    }
}
