import Foundation
import Testing
@testable import Till

@MainActor
@Suite struct CreationFlowIconTests {

    private func make(_ icons: MockIcons?) throws -> (Harness, CreationFlow) {
        let h = try Harness()
        let f = CreationFlow(
            store: h.store, clock: { h.clock.now },
            calendar: TestClock.calendar, timeZone: TestClock.zone, iconProvider: icons)
        return (h, f)
    }

    private func asset(_ id: String, monotone: Bool) -> IconAsset {
        IconAsset(id: id, monotone: monotone, fileURL: URL(fileURLWithPath: "/tmp/\(id).png"))
    }

    private func choice(_ id: String) -> IconChoice {
        IconChoice(id: id, monotone: true, collectionName: "Material Design Icons", licenseTitle: "Apache 2.0")
    }

    @Test func builtInIconNeverTouchesTheNetwork() async throws {
        let icons = MockIcons()
        let (h, f) = try make(icons)
        f.input = "in 5 min"
        await f.submit()
        #expect(h.store.chips.first?.iconId == FallbackIcons.defaultID)
        #expect(icons.fetched.isEmpty)
    }

    @Test func pickingABundledIconNeverTouchesTheNetwork() async throws {
        let icons = MockIcons()
        let (h, f) = try make(icons)
        f.selectIcon(IconChoice(id: "logos:claude-icon", monotone: false, collectionName: "SVG Logos", licenseTitle: "CC0"))
        f.input = "in 5 min"
        await f.submit()
        #expect(h.store.chips.first?.iconId == "logos:claude-icon")
        #expect(h.store.chips.first?.iconMonotone == false)
        #expect(icons.fetched.isEmpty)
    }

    @Test func pickedIconIsFetchedAtCreationAndItsDetectedFlagWins() async throws {
        let icons = MockIcons(fetch: .success(asset("logos:apple", monotone: false)))
        let (h, f) = try make(icons)
        f.selectIcon(choice("logos:apple"))        // picker hint said monotone
        f.input = "in 5 min"
        await f.submit()
        let chip = try #require(h.store.chips.first)
        #expect(chip.iconId == "logos:apple")
        #expect(chip.iconMonotone == false)
        #expect(icons.fetched == ["logos:apple"])
        #expect(f.selectedIcon == IconChoice.fallbackDefault)     // reset for the next chip
        #expect(!f.isFetchingIcon && !f.isBusy)
    }

    @Test func fetchFailureLeavesNoChipAndKeepsTheSelectionForRetry() async throws {
        let icons = MockIcons(fetch: .failure(IconError.network))
        let (h, f) = try make(icons)
        f.selectIcon(choice("mdi:coffee"))
        f.input = "in 5 min"
        await f.submit()
        #expect(h.store.chips.isEmpty)
        #expect(f.errorHint == IconError.network.hint)
        #expect(f.selectedIcon.id == "mdi:coffee")
        #expect(f.input == "in 5 min")
        #expect(!f.isFetchingIcon && !f.isBusy)
    }

    @Test func fetchHappensAfterTheTimePromptNotBefore() async throws {
        let icons = MockIcons(fetch: .success(asset("mdi:coffee", monotone: true)))
        let (h, f) = try make(icons)
        f.selectIcon(choice("mdi:coffee"))
        f.input = "Nov 15"
        await f.submit()                           // parse -> time prompt, nothing fetched yet
        #expect(icons.fetched.isEmpty)
        await f.confirmTime()
        #expect(icons.fetched == ["mdi:coffee"])
        #expect(h.store.chips.count == 1)
    }

    @Test func dismissingDuringTheFetchDropsTheResult() async throws {
        let icons = MockIcons(fetch: .success(asset("mdi:coffee", monotone: true)))
        let (h, f) = try make(icons)
        icons.setHook { f.cancelInFlight() }        // popover dismissed while the fetch is in flight
        f.selectIcon(choice("mdi:coffee"))
        f.input = "in 5 min"
        await f.submit()
        #expect(h.store.chips.isEmpty)
        #expect(f.errorHint == nil)
        #expect(!f.isBusy && !f.isFetchingIcon)
    }

    @Test func nonBuiltInIconWithoutAProviderIsATypedError() async throws {
        let (h, f) = try make(nil)
        f.selectIcon(choice("mdi:coffee"))
        f.input = "in 5 min"
        await f.submit()
        #expect(h.store.chips.isEmpty)
        #expect(f.errorHint == IconError.invalidIconID.hint)
    }

    @Test func editModeNeverFetches() async throws {
        let icons = MockIcons()
        let (h, f) = try make(icons)
        let id = try await h.create(in: 3600)
        f.beginEdit(id: id)
        f.input = "in 2 hours"
        await f.submit()
        #expect(h.chip(id)?.deadline == h.clock.now.addingTimeInterval(7200))
        #expect(icons.fetched.isEmpty)
    }
}

@MainActor
@Suite struct IconPickerModelTests {
    private func result(_ id: String) -> IconSearchResult {
        IconSearchResult(id: id, collectionName: "Material Design Icons", licenseTitle: "Apache 2.0", paletteHint: false)
    }

    @Test func successfulSearchPublishesResults() async {
        let icons = MockIcons(search: .success([result("mdi:coffee")]))
        let model = IconPickerModel(provider: icons)
        model.query = "  coffee "
        await model.search()
        #expect(model.results.map(\.id) == ["mdi:coffee"])
        #expect(model.status == .idle)
        #expect(icons.searched == ["coffee"])
    }

    @Test func emptyResultsAreReported() async {
        let model = IconPickerModel(provider: MockIcons(search: .success([])))
        model.query = "zzzz"
        await model.search()
        #expect(model.status == .empty && model.results.isEmpty)
    }

    @Test func failureShowsAHintAndClearsResults() async {
        let model = IconPickerModel(provider: MockIcons(search: .failure(IconError.network)))
        model.query = "coffee"
        await model.search()
        #expect(model.status == .failed(IconError.network.hint))
        #expect(model.results.isEmpty)
    }

    @Test func blankQueryNeverSearches() async {
        let icons = MockIcons()
        let model = IconPickerModel(provider: icons)
        model.query = "   "
        await model.search()
        #expect(model.status == .failed(IconError.invalidQuery.hint))
        #expect(icons.searched.isEmpty)
    }

    @Test func resultArrivingAfterDismissIsDropped() async {
        let icons = MockIcons(search: .success([result("mdi:coffee")]))
        let model = IconPickerModel(provider: icons)
        icons.setHook { model.cancel() }
        model.query = "coffee"
        await model.search()
        #expect(model.results.isEmpty)
        #expect(model.status != .searching)
    }

    @Test func disclosureNamesCollectionLicenseAndTint() {
        #expect(IconPickerModel.disclosure(for: result("mdi:coffee"))
                == "Material Design Icons · Apache 2.0 · single color — takes the chip’s color")
        let palette = IconSearchResult(id: "logos:apple", collectionName: "SVG Logos", licenseTitle: "CC0 1.0", paletteHint: true)
        #expect(IconPickerModel.disclosure(for: palette) == "SVG Logos · CC0 1.0 · multicolor — keeps its own colors")
        let unknown = IconSearchResult(id: "x:y", collectionName: nil, licenseTitle: nil, paletteHint: nil)
        #expect(IconPickerModel.disclosure(for: unknown) == "color is detected when added")
        #expect(IconPickerModel.disclosure(for: IconChoice.fallbackDefault) == "Built-in icon")
    }
}

@MainActor
@Suite struct IconPickerStateTests {
    private func result(_ id: String) -> IconSearchResult {
        IconSearchResult(id: id, collectionName: "Material Design Icons", licenseTitle: "Apache 2.0", paletteHint: false)
    }

    @Test func statusTextCoversEveryState() {
        #expect(IconPickerModel.statusText(for: .idle, query: "coffee") == nil)
        #expect(IconPickerModel.statusText(for: .searching, query: "coffee") == "Searching…")
        #expect(IconPickerModel.statusText(for: .empty, query: "qzxv")
                == "No icons match “qzxv”. Try a simpler word, such as coffee or bell.")
        #expect(IconPickerModel.statusText(for: .failed("Hint."), query: "x") == "Hint.")
    }

    @Test func awkwardQueriesStayIntactInTheNoResultsText() {        // Review Focus 5
        let q = "“it’s” \"quoted\" " + String(repeating: "a", count: 40)
        #expect(IconPickerModel.statusText(for: .empty, query: q)!.contains(q))
    }

    @Test func searchRecordsTheTrimmedQueryAndHighlightsTheFirstResult() async {
        let model = IconPickerModel(provider: MockIcons(search: .success([result("mdi:coffee"), result("mdi:tea")])))
        model.query = "  coffee "
        await model.search()
        #expect(model.lastQuery == "coffee")
        #expect(model.highlighted?.id == "mdi:coffee")
    }

    @Test func emptyAndFailedSearchesClearTheHighlight() async {
        let empty = IconPickerModel(provider: MockIcons(search: .success([])))
        empty.highlighted = result("mdi:coffee")
        empty.query = "zzzz"
        await empty.search()
        #expect(empty.highlighted == nil)

        let failed = IconPickerModel(provider: MockIcons(search: .failure(IconError.offline)))
        failed.highlighted = result("mdi:coffee")
        failed.query = "coffee"
        await failed.search()
        #expect(failed.highlighted == nil)
        #expect(failed.status == .failed(IconError.offline.hint))
    }

    @Test func onlyAPageOfResultsIsShown() async {
        let many = (0..<64).map { result("mdi:icon-\($0)") }
        let model = IconPickerModel(provider: MockIcons(search: .success(many)))
        model.query = "icon"
        await model.search()
        #expect(model.results.count == 64)
        #expect(model.visibleResults.count == IconPickerModel.visibleLimit)
        #expect(IconPickerModel.visibleLimit == 12)
        #expect(model.visibleResults.first?.id == "mdi:icon-0")
    }
}
