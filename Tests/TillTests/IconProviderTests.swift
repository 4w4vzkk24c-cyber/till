import AppKit
import Foundation
import Testing
@testable import Till

@Suite struct IconIDTests {
    @Test func validIDsParse() {
        #expect(IconID.parse("mdi:timer")?.prefix == "mdi")
        #expect(IconID.parse("mdi:timer-outline")?.name == "timer-outline")
        #expect(IconID.parse("fa6-solid:house-2") != nil)
    }

    @Test(arguments: ["mdi", "mdi:", ":timer", "MDI:timer", "mdi:Timer", "a:b:c", "../x:y",
                      "mdi:ti/mer", "a--b:c", "mdi:-x", "mdi:x-", "mdi:ti mer", "mdi:tímer", ""])
    func invalidIDsAreRejected(_ id: String) {
        #expect(IconID.parse(id) == nil)
    }

    @Test func fileStemRoundTrips() {
        let stem = IconID.fileStem(prefix: "mdi", name: "timer-outline")
        #expect(stem == "mdi--timer-outline")
        #expect(IconID.id(fromFileStem: stem) == "mdi:timer-outline")
        #expect(IconID.id(fromFileStem: "garbage") == nil)
        #expect(IconID.id(fromFileStem: "a--b--c") == nil)
    }
}

@Suite struct SVGColorInspectorTests {
    @Test(arguments: [
        ##"<svg><path fill="#fff" d="M0 0"/></svg>"##,
        ##"<svg><path fill="#FFFFFF" d="M0 0"/></svg>"##,
        ##"<svg><path fill="white"/></svg>"##,
        ##"<svg><path fill="currentColor"/></svg>"##,
        ##"<svg fill="none"><path stroke="#ffffff" stroke-width="2"/></svg>"##,
        ##"<svg><path style="fill:#fff;stroke:none"/></svg>"##,
        ##"<svg><path fill-rule="evenodd" clip-rule="evenodd" fill="#fff"/></svg>"##,
        ##"<svg><path fill='#fff'/></svg>"##,
        ##"<svg><path fill="rgb(255, 255, 255)"/></svg>"##,
        ##"<svg><path d="M0 0h1v1z"/></svg>"##,
    ])
    func monotone(_ svg: String) {
        #expect(SVGColorInspector.isMonotone(svg))
    }

    @Test(arguments: [
        ##"<svg><path fill="#e91e63"/></svg>"##,
        ##"<svg><path fill="#ffffff"/><path fill="#000"/></svg>"##,
        ##"<svg><path style="fill: #ff0000"/></svg>"##,
        ##"<svg><defs><linearGradient id="a"><stop stop-color="#f00"/></linearGradient></defs><path fill="url(#a)"/></svg>"##,
        ##"<svg><path stroke="red"/></svg>"##,
    ])
    func palette(_ svg: String) {
        #expect(!SVGColorInspector.isMonotone(svg))
    }

    @Test func extractsValuesWithoutMatchingLookalikes() {
        let svg = ##"<svg><path fill-opacity="0.5" stroke-width="2" fill="#fff" stroke="none"/></svg>"##
        #expect(SVGColorInspector.colorValues(in: svg) == ["#fff", "none"])
    }
}

@Suite struct IconProviderSearchTests {
    @Test func buildsRequestAndParsesResults() async throws {
        let network = MockNetwork { _ in (Data(Samples.searchJSON.utf8), 200) }
        let provider = makeProvider(network: network, directory: try TempDir.make())
        let results = try await provider.search(query: "  timer ", prefix: nil, limit: 64)

        #expect(network.requests.map(\.absoluteString) == ["https://api.iconify.design/search?query=timer&limit=64"])
        #expect(results.map(\.id) == ["mdi:timer", "mdi:timer-outline", "logos:apple"])   // "bad id" skipped
        #expect(results[0].collectionName == "Material Design Icons")
        #expect(results[0].licenseTitle == "Apache 2.0")
        #expect(results[0].paletteHint == false)
        #expect(results[2].paletteHint == true)
        #expect(results[2].licenseTitle == "CC0 1.0")
    }

    @Test func prefixAndLimitAreSentAndClamped() async throws {
        let network = MockNetwork { _ in (Data(Samples.searchJSON.utf8), 200) }
        let provider = makeProvider(network: network, directory: try TempDir.make())
        _ = try await provider.search(query: "timer", prefix: "mdi", limit: 500)
        #expect(network.requests.first?.absoluteString
                == "https://api.iconify.design/search?query=timer&limit=64&prefix=mdi")
    }

    @Test func invalidQueriesNeverHitTheNetwork() async throws {
        let network = MockNetwork.serving("{}")
        let provider = makeProvider(network: network, directory: try TempDir.make())
        await #expect(throws: IconError.invalidQuery) { try await provider.search(query: "   ", prefix: nil, limit: 64) }
        await #expect(throws: IconError.invalidQuery) { try await provider.search(query: String(repeating: "a", count: 65), prefix: nil, limit: 64) }
        await #expect(throws: IconError.invalidQuery) { try await provider.search(query: "x", prefix: "BAD/prefix", limit: 64) }
        #expect(network.requests.isEmpty)
    }

    @Test func httpAndTransportFailuresAreTyped() async throws {
        let dir = try TempDir.make()
        let bad = makeProvider(network: .serving("{}", status: 500), directory: dir)
        await #expect(throws: IconError.badStatus(500)) { try await bad.search(query: "x", prefix: nil, limit: 64) }
        let offline = makeProvider(network: .offline, directory: dir)
        await #expect(throws: IconError.network) { try await offline.search(query: "x", prefix: nil, limit: 64) }
        let garbage = makeProvider(network: .serving("not json"), directory: dir)
        await #expect(throws: IconError.decodeFailed) { try await garbage.search(query: "x", prefix: nil, limit: 64) }
    }

    @Test func malformedCollectionMetadataDegradesToNil() async throws {
        let json = #"{"icons":["mdi:timer"],"collections":{"mdi":{"name":42,"license":"oops","palette":"yes"}}}"#
        let provider = makeProvider(network: .serving(json), directory: try TempDir.make())
        let results = try await provider.search(query: "timer", prefix: nil, limit: 64)
        #expect(results.map(\.id) == ["mdi:timer"])
        #expect(results[0].collectionName == nil && results[0].licenseTitle == nil && results[0].paletteHint == nil)
    }

    @Test func cancellationIsNotReportedAsNetworkFailure() async throws {
        let cancelled = MockNetwork { _ in throw URLError(.cancelled) }
        let provider = makeProvider(network: cancelled, directory: try TempDir.make())
        await #expect(throws: CancellationError.self) { try await provider.search(query: "x", prefix: nil, limit: 64) }
    }
}

@Suite struct IconProviderFetchTests {
    @Test func fetchesCachesAndReportsMonotone() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = MockNetwork.serving(Samples.monotoneSVG)
        let provider = makeProvider(network: network, directory: dir)

        let asset = try await provider.fetch(id: "mdi:timer")
        #expect(network.requests.map(\.absoluteString)
                == ["https://api.iconify.design/mdi/timer.svg?color=%23ffffff&height=256"])
        #expect(asset.id == "mdi:timer" && asset.monotone)
        #expect(asset.fileURL == dir.appendingPathComponent("mdi--timer.png"))
        #expect(try Data(contentsOf: asset.fileURL) == Samples.fakePNG)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mdi--timer.json").path))
    }

    @Test func paletteIconIsDetectedAndNotMonotone() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = makeProvider(network: .serving(Samples.paletteSVG), directory: dir)
        let asset = try await provider.fetch(id: "logos:apple")
        #expect(!asset.monotone)
    }

    @Test func cacheHitMakesNoNetworkCall() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = MockNetwork.serving(Samples.paletteSVG)
        let provider = makeProvider(network: network, directory: dir)
        _ = try await provider.fetch(id: "logos:apple")
        let again = try await provider.fetch(id: "logos:apple")
        #expect(network.requests.count == 1)
        #expect(!again.monotone)                       // flag survives via the sidecar
    }

    /// Offline invariant (design §7.2 invariant 1): with the icon cached, a fresh provider
    /// whose network always fails still succeeds and makes zero requests.
    @Test func offlineRoundTripWithCachedIconMakesZeroRequests() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await makeProvider(network: .serving(Samples.monotoneSVG), directory: dir).fetch(id: "mdi:timer")

        let offline = MockNetwork.offline
        let second = makeProvider(network: offline, directory: dir)
        let asset = try await second.fetch(id: "mdi:timer")
        #expect(asset.monotone)
        #expect(offline.requests.isEmpty)
    }

    @Test func uncachedIconOfflineFailsWithTypedError() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = makeProvider(network: .offline, directory: dir)
        await #expect(throws: IconError.network) { try await provider.fetch(id: "mdi:timer") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test(arguments: ["mdi", "MDI:Timer", "../etc:passwd", "a:b/c", "a--b:c", ""])
    func invalidIDsNeverHitTheNetwork(_ id: String) async throws {
        let network = MockNetwork.serving(Samples.monotoneSVG)
        let provider = makeProvider(network: network, directory: try TempDir.make())
        await #expect(throws: IconError.invalidIconID) { try await provider.fetch(id: id) }
        #expect(network.requests.isEmpty)
    }

    @Test func badResponsesWriteNothing() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: IconError.badStatus(404)) {
            try await makeProvider(network: .serving("", status: 404), directory: dir).fetch(id: "mdi:nope")
        }
        await #expect(throws: IconError.decodeFailed) {
            try await makeProvider(network: .serving("<html>hi</html>"), directory: dir).fetch(id: "mdi:html")
        }
        await #expect(throws: IconError.decodeFailed) {
            try await makeProvider(network: .serving(""), directory: dir).fetch(id: "mdi:empty")
        }
        let huge = "<svg>" + String(repeating: "x", count: IconProvider.maxSVGBytes) + "</svg>"
        await #expect(throws: IconError.decodeFailed) {
            try await makeProvider(network: .serving(huge), directory: dir).fetch(id: "mdi:huge")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func rasterizerFailureWritesNothing() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = makeProvider(network: .serving(Samples.monotoneSVG), directory: dir) { _ in throw TestFailure() }
        await #expect(throws: IconError.rasterizeFailed) { try await provider.fetch(id: "mdi:timer") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func missingSidecarIsACacheMiss() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let network = MockNetwork.serving(Samples.monotoneSVG)
        let provider = makeProvider(network: network, directory: dir)
        _ = try await provider.fetch(id: "mdi:timer")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("mdi--timer.json"))
        #expect(await provider.cachedAsset(id: "mdi:timer") == nil)
        _ = try await provider.fetch(id: "mdi:timer")
        #expect(network.requests.count == 2)
    }

    @Test func cancellationPropagatesAsCancellation() async throws {
        let provider = makeProvider(
            network: MockNetwork { _ in throw CancellationError() }, directory: try TempDir.make())
        await #expect(throws: CancellationError.self) { try await provider.fetch(id: "mdi:timer") }
    }
}

@Suite struct IconEvictionTests {
    @Test func unreferencedOldEntriesAreRemovedAndReferencedKept() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = makeProvider(network: .serving(Samples.monotoneSVG), directory: dir)
        for id in ["mdi:keep", "mdi:drop"] { _ = try await provider.fetch(id: id) }

        let later = Date().addingTimeInterval(IconProvider.evictionGrace + 60)
        let removed = await provider.evictUnreferenced(["mdi:keep"], now: later)
        #expect(removed == ["mdi:drop"])
        #expect(await provider.cachedAsset(id: "mdi:keep") != nil)
        #expect(await provider.cachedAsset(id: "mdi:drop") == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("mdi--drop.png").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("mdi--drop.json").path))
    }

    @Test func recentUnreferencedEntriesSurviveTheGracePeriod() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = makeProvider(network: .serving(Samples.monotoneSVG), directory: dir)
        _ = try await provider.fetch(id: "mdi:fresh")
        let removed = await provider.evictUnreferenced([], now: Date())
        #expect(removed.isEmpty)
        #expect(await provider.cachedAsset(id: "mdi:fresh") != nil)
    }

    @Test func missingDirectoryIsHarmless() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        let provider = makeProvider(network: .offline, directory: missing)
        #expect(await provider.evictUnreferenced([]).isEmpty)
    }
}

/// R1 / V7: real SVG decode and rasterization on this host. This is the one test that
/// exercises Apple's SVG path; the others use a fake rasterizer.
@Suite struct SVGRasterizerTests {
    @Test func rendersAWhiteSquareWithTransparentSurroundings() throws {
        let png = try SVGRasterizer.pngData(from: Data(Samples.monotoneSVG.utf8), pixels: 256)
        #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 256 && rep.pixelsHigh == 256)
        let center = try #require(rep.colorAt(x: 128, y: 128))
        #expect(center.alphaComponent > 0.9)
        #expect(center.redComponent > 0.9 && center.greenComponent > 0.9 && center.blueComponent > 0.9)
        let corner = try #require(rep.colorAt(x: 2, y: 2))
        #expect(corner.alphaComponent < 0.1)
    }

    @Test func garbageIsATypedError() {
        #expect(throws: SVGRasterizerError.decodeFailed) {
            try SVGRasterizer.pngData(from: Data("not an svg".utf8))
        }
    }
}
