import Foundation

/// Icon search, fetch, rasterize and cache (design §5, §7.2). The only unit that touches
/// the network, and only from the creation / picker path. After a chip exists nothing here
/// is called (offline invariant, pinned by `IconProviderTests`).
///
/// Cache: `<cacheDirectory>/{prefix}--{name}.png` plus a tiny `{prefix}--{name}.json`
/// sidecar holding the monotone flag, because the PNG alone cannot say whether the
/// original was single-colour. A cache entry needs both files; otherwise it is a miss.
actor IconProvider: IconFetching {
    typealias Rasterizer = @Sendable (Data) throws -> Data

    static let apiHost = "api.iconify.design"
    static let maxSVGBytes = 256 * 1024
    /// Unreferenced cache files younger than this are kept so an icon fetched for a chip
    /// that is still being created is not evicted underneath it.
    static let evictionGrace: TimeInterval = 300

    private struct Meta: Codable { let monotone: Bool }

    private let network: any IconNetworking
    private let cacheDirectory: URL
    private let rasterize: Rasterizer

    init(
        network: any IconNetworking,
        cacheDirectory: URL,
        rasterizer: @escaping Rasterizer = { try SVGRasterizer.pngData(from: $0) }
    ) {
        self.network = network
        self.cacheDirectory = cacheDirectory
        self.rasterize = rasterizer
    }

    /// `~/Library/Application Support/Till/icons`, the path `IconCache` reads.
    static func defaultCacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return base.appendingPathComponent("Till/icons", isDirectory: true)
    }

    // MARK: - Search

    func search(query: String, prefix: String? = nil, limit: Int = 64) async throws -> [IconSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { throw IconError.invalidQuery }
        if let prefix, !IconID.isValidPart(prefix) { throw IconError.invalidQuery }

        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.apiHost
        components.path = "/search"
        var items = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 64))),
        ]
        if let prefix { items.append(URLQueryItem(name: "prefix", value: prefix)) }
        components.queryItems = items
        guard let url = components.url else { throw IconError.invalidQuery }

        let (body, status) = try await get(url, operation: "search")
        guard status == 200 else {
            IconLog.recordStatus(status, operation: "search")
            throw IconError.badStatus(status)
        }
        guard let response = try? JSONDecoder().decode(SearchResponse.self, from: body) else {
            IconLog.logger.error("search decode failed")
            throw IconError.decodeFailed
        }
        IconLog.note("search ok: \(response.icons.count) ids")
        return response.icons.compactMap { id in
            guard let parsed = IconID.parse(id) else { return nil }
            let collection = response.collections[parsed.prefix]
            return IconSearchResult(
                id: id, collectionName: collection?.name,
                licenseTitle: collection?.licenseTitle, paletteHint: collection?.palette)
        }
    }

    // MARK: - Fetch

    func fetch(id: String) async throws -> IconAsset {
        guard let parsed = IconID.parse(id) else { throw IconError.invalidIconID }
        if let cached = cachedAsset(id: id) { return cached }   // no network

        guard let url = URL(
            string: "https://\(Self.apiHost)/\(parsed.prefix)/\(parsed.name).svg?color=%23ffffff&height=256")
        else { throw IconError.invalidIconID }

        let (body, status) = try await get(url, operation: "fetch")
        guard status == 200 else {
            IconLog.recordStatus(status, operation: "fetch")
            throw IconError.badStatus(status)
        }
        guard !body.isEmpty, body.count <= Self.maxSVGBytes,
              let svg = String(data: body, encoding: .utf8), svg.contains("<svg") else {
            IconLog.logger.error("fetch decode failed")
            throw IconError.decodeFailed
        }
        let monotone = SVGColorInspector.isMonotone(svg)

        let png: Data
        do { png = try rasterize(body) } catch { throw IconError.rasterizeFailed }

        let stem = IconID.fileStem(prefix: parsed.prefix, name: parsed.name)
        let pngURL = cacheDirectory.appendingPathComponent("\(stem).png")
        let metaURL = cacheDirectory.appendingPathComponent("\(stem).json")
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try png.write(to: pngURL, options: .atomic)
            try JSONEncoder().encode(Meta(monotone: monotone)).write(to: metaURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: pngURL)
            try? FileManager.default.removeItem(at: metaURL)
            throw IconError.cacheWriteFailed
        }
        return IconAsset(id: id, monotone: monotone, fileURL: pngURL)
    }

    /// A cache entry needs both files. Never touches the network.
    func cachedAsset(id: String) -> IconAsset? {
        guard let parsed = IconID.parse(id) else { return nil }
        let stem = IconID.fileStem(prefix: parsed.prefix, name: parsed.name)
        let pngURL = cacheDirectory.appendingPathComponent("\(stem).png")
        let metaURL = cacheDirectory.appendingPathComponent("\(stem).json")
        guard FileManager.default.fileExists(atPath: pngURL.path),
              let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return nil }
        return IconAsset(id: id, monotone: meta.monotone, fileURL: pngURL)
    }

    // MARK: - Eviction (design §5 step 3: evicted when no chip references it)

    /// Removes cache entries no chip references. Entries modified within `grace` seconds
    /// are kept. Returns the ids removed.
    @discardableResult
    func evictUnreferenced(
        _ referenced: Set<String>, grace: TimeInterval = IconProvider.evictionGrace, now: Date = Date()
    ) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path) else {
            return []
        }
        var removed: [String] = []
        var stems = Set<String>()
        for name in names {
            let url = URL(fileURLWithPath: name)
            if url.pathExtension == "png" || url.pathExtension == "json" {
                stems.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        for stem in stems.sorted() {
            guard let id = IconID.id(fromFileStem: stem), !referenced.contains(id) else { continue }
            let pngURL = cacheDirectory.appendingPathComponent("\(stem).png")
            let metaURL = cacheDirectory.appendingPathComponent("\(stem).json")
            let newest = [pngURL, metaURL].compactMap { url -> Date? in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                return attributes?[.modificationDate] as? Date
            }.max()
            if let newest, now.timeIntervalSince(newest) < grace { continue }
            try? FileManager.default.removeItem(at: pngURL)
            try? FileManager.default.removeItem(at: metaURL)
            removed.append(id)
        }
        return removed
    }

    // MARK: - Networking

    private func get(_ url: URL, operation: String) async throws -> (Data, Int) {
        do {
            let result = try await network.get(url)
            return (result.body, result.status)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            IconLog.record(error, operation: operation)
            throw IconFailure.classify(error)
        }
    }
}

/// Tolerant decoding of `GET /search`: only `icons` is required; collection metadata that
/// is missing or oddly typed degrades to nil rather than failing the search.
private struct SearchResponse: Decodable {
    struct Collection: Decodable {
        let name: String?
        let licenseTitle: String?
        let palette: Bool?

        private enum CodingKeys: String, CodingKey { case name, license, palette }
        private struct License: Decodable { let title: String?; let spdx: String? }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            palette = try? c.decodeIfPresent(Bool.self, forKey: .palette)
            let license = try? c.decodeIfPresent(License.self, forKey: .license)
            licenseTitle = license?.title ?? license?.spdx
        }
    }

    let icons: [String]
    let collections: [String: Collection]

    private enum CodingKeys: String, CodingKey { case icons, collections }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        icons = try c.decode([String].self, forKey: .icons)
        collections = (try? c.decodeIfPresent([String: Collection].self, forKey: .collections)) ?? [:]
    }
}
