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

    var query = ""
    private(set) var results: [IconSearchResult] = []
    private(set) var status: Status = .idle

    @ObservationIgnored let provider: any IconFetching
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(provider: any IconFetching) {
        self.provider = provider
    }

    func startSearch() {
        IconLog.note("picker: search submitted")
        searchTask?.cancel()
        searchTask = Task { await self.search() }
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        generation += 1
        let gen = generation
        guard !trimmed.isEmpty else {
            results = []
            status = .failed(IconError.invalidQuery.hint)
            return
        }
        status = .searching
        do {
            let found = try await provider.search(query: trimmed, prefix: nil, limit: 64)
            guard gen == generation else { return }
            results = found
            status = found.isEmpty ? .empty : .idle
            IconLog.note("picker: search finished, \(found.count) results")
        } catch is CancellationError {
            return
        } catch {
            guard gen == generation else { return }
            results = []
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

struct IconPickerView: View {
    @Bindable var model: IconPickerModel
    let creation: CreationFlow

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search icons, e.g. coffee", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.startSearch() }
                .accessibilityLabel("Search icons")

            // Built-in set: always available, including when the service is unreachable.
            HStack(spacing: 6) {
                ForEach(FallbackIcons.all, id: \.self) { id in
                    Button {
                        creation.selectIcon(IconChoice(id: id, monotone: true, collectionName: nil, licenseTitle: nil))
                    } label: {
                        ChipIconView(iconId: id, monotone: true, tint: .primary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Built-in icon \(FallbackIcons.symbolName(for: id) ?? id)")
                }
            }

            switch model.status {
            case .searching:
                Text("Searching…").font(.caption).foregroundStyle(.secondary)
            case .empty:
                Text("No icons found.").font(.caption).foregroundStyle(.secondary)
            case .failed(let hint):
                Text(hint).font(.caption).foregroundStyle(.red)
            case .idle:
                EmptyView()
            }

            if !model.results.isEmpty {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(model.results) { result in
                            Button {
                                creation.selectIcon(
                                    IconChoice(
                                        id: result.id, monotone: !(result.paletteHint ?? false),
                                        collectionName: result.collectionName,
                                        licenseTitle: result.licenseTitle))
                            } label: {
                                IconPreviewCell(provider: model.provider, result: result)
                            }
                            .buttonStyle(.plain)
                            .help(IconPickerModel.disclosure(for: result))
                            .accessibilityLabel(result.id)
                            .accessibilityHint(IconPickerModel.disclosure(for: result))
                        }
                    }
                }
                .frame(maxHeight: 170)
            }

            Text("Icons come from Iconify. Each set’s license is shown when you pick one.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// One search result. Fetching the preview also warms the disk cache, so picking it and
/// creating the chip later is a cache hit with no further network call.
struct IconPreviewCell: View {
    let provider: any IconFetching
    let result: IconSearchResult

    @State private var image: NSImage?
    @State private var monotone = true
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                if monotone {
                    Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                        .foregroundStyle(.primary)
                } else {
                    Image(nsImage: image).renderingMode(.original).resizable().scaledToFit()
                }
            } else if failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                Color.clear
            }
        }
        .frame(width: 32, height: 32)
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
