import Foundation
@testable import Till

enum Samples {
    static let monotoneSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 24 24"><path fill="#ffffff" d="M2 2h20v20H2z"/></svg>"##
    static let paletteSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 24 24"><path fill="#e91e63" d="M2 2h10v20H2z"/><path fill="#ffffff" d="M12 2h10v20H12z"/></svg>"##

    static let searchJSON = #"""
    {"icons":["mdi:timer","mdi:timer-outline","bad id","logos:apple"],"total":4,"limit":64,"start":0,
     "collections":{
       "mdi":{"name":"Material Design Icons","license":{"title":"Apache 2.0","spdx":"Apache-2.0"},"palette":false},
       "logos":{"name":"SVG Logos","license":{"title":"CC0 1.0"},"palette":true}}}
    """#

    static let fakePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}

enum TempDir {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("till-icon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Records every request; the handler decides the response. Replaces a URLProtocol mock:
/// the offline invariant only needs "how many requests were made".
final class MockNetwork: IconNetworking, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []
    private let handler: @Sendable (URL) throws -> (Data, Int)

    init(_ handler: @escaping @Sendable (URL) throws -> (Data, Int)) {
        self.handler = handler
    }

    var requests: [URL] { lock.withLock { recorded } }

    func get(_ url: URL) async throws -> (body: Data, status: Int) {
        lock.withLock { recorded.append(url) }
        let result = try handler(url)
        return (result.0, result.1)
    }

    static func serving(_ svg: String, status: Int = 200) -> MockNetwork {
        MockNetwork { _ in (Data(svg.utf8), status) }
    }

    static var offline: MockNetwork {
        MockNetwork { _ in throw URLError(.notConnectedToInternet) }
    }
}

struct TestFailure: Error {}

func makeProvider(
    network: MockNetwork, directory: URL,
    rasterizer: @escaping IconProvider.Rasterizer = { _ in Samples.fakePNG }
) -> IconProvider {
    IconProvider(network: network, cacheDirectory: directory, rasterizer: rasterizer)
}

/// Controllable `IconFetching` for the creation flow and picker model.
final class MockIcons: IconFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var fetchedIDs: [String] = []
    private var searchedQueries: [String] = []
    private var fetchResult: Result<IconAsset, Error>
    private var searchResult: Result<[IconSearchResult], Error>
    private var hook: (@MainActor @Sendable () -> Void)?

    init(
        fetch: Result<IconAsset, Error> = .failure(TestFailure()),
        search: Result<[IconSearchResult], Error> = .success([])
    ) {
        fetchResult = fetch
        searchResult = search
    }

    var fetched: [String] { lock.withLock { fetchedIDs } }
    var searched: [String] { lock.withLock { searchedQueries } }

    func setHook(_ hook: (@MainActor @Sendable () -> Void)?) {
        lock.withLock { self.hook = hook }
    }

    func fetch(id: String) async throws -> IconAsset {
        let (result, hook) = lock.withLock { () -> (Result<IconAsset, Error>, (@MainActor @Sendable () -> Void)?) in
            fetchedIDs.append(id)
            return (fetchResult, self.hook)
        }
        if let hook { await MainActor.run { hook() } }
        return try result.get()
    }

    func search(query: String, prefix: String?, limit: Int) async throws -> [IconSearchResult] {
        let (result, hook) = lock.withLock { () -> (Result<[IconSearchResult], Error>, (@MainActor @Sendable () -> Void)?) in
            searchedQueries.append(query)
            return (searchResult, self.hook)
        }
        if let hook { await MainActor.run { hook() } }
        return try result.get()
    }
}
