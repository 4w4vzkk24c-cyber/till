import Foundation

/// Iconify icon ids are `prefix:name`. Both parts are restricted to lowercase ASCII
/// letters, digits and single hyphens, which makes the id safe to put in a URL path and
/// in a cache file name (`prefix--name.png`) and keeps that mapping reversible.
enum IconID {
    static func isValidPart(_ part: String) -> Bool {
        guard !part.isEmpty, part.count <= 64,
              !part.hasPrefix("-"), !part.hasSuffix("-"), !part.contains("--") else { return false }
        return part.allSatisfy { ch in
            ch.isASCII && (ch.isLowercase || ch.isNumber || ch == "-")
        }
    }

    static func parse(_ id: String) -> (prefix: String, name: String)? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, isValidPart(parts[0]), isValidPart(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    static func fileStem(prefix: String, name: String) -> String { "\(prefix)--\(name)" }

    static func id(fromFileStem stem: String) -> String? {
        let parts = stem.components(separatedBy: "--")
        guard parts.count == 2, isValidPart(parts[0]), isValidPart(parts[1]) else { return nil }
        return "\(parts[0]):\(parts[1])"
    }
}

struct IconSearchResult: Sendable, Equatable, Identifiable {
    let id: String
    let collectionName: String?
    let licenseTitle: String?
    /// Collection-level `palette` flag from the search API. A hint for the picker's
    /// disclosure only; the fetched asset's own detection is authoritative (design §5).
    let paletteHint: Bool?
}

struct IconAsset: Sendable, Equatable {
    let id: String
    let monotone: Bool
    let fileURL: URL
}

/// What the add field will use for the next chip. `monotone` is a hint for sf:/search
/// choices; for fetched icons the asset's detected value replaces it at creation.
struct IconChoice: Sendable, Equatable {
    let id: String
    let monotone: Bool
    let collectionName: String?
    let licenseTitle: String?

    static let fallbackDefault = IconChoice(
        id: FallbackIcons.defaultID, monotone: true, collectionName: nil, licenseTitle: nil)

    var isBuiltIn: Bool { FallbackIcons.symbolName(for: id) != nil }
}

enum IconError: Error, Equatable, Sendable {
    case invalidQuery
    case invalidIconID
    case network
    case offline
    case tls
    case timedOut
    case badStatus(Int)
    case decodeFailed
    case rasterizeFailed
    case cacheWriteFailed

    /// Inline text for the add field / picker. No dialogs.
    var hint: String {
        switch self {
        case .invalidQuery: return "Type a word to search icons, e.g. “coffee”."
        case .invalidIconID: return "That icon can’t be used. Pick another."
        case .network:
            return "Can’t reach the icon service. Check your connection, or pick a built-in icon."
        case .badStatus(let code):
            return "The icon service returned an error (\(code)). Try again, or pick a built-in icon."
        case .offline:
            return "You’re offline. Pick a built-in icon, or try again once you’re connected."
        case .tls:
            return "Can’t make a secure connection to the icon service. Check your VPN or proxy, or pick a built-in icon."
        case .timedOut:
            return "The icon service didn’t answer in time. Try again, or pick a built-in icon."
        case .decodeFailed, .rasterizeFailed, .cacheWriteFailed:
            return "Couldn’t prepare that icon. Pick another or a built-in one."
        }
    }
}

/// The only unit that may touch the network (design §7.2).
protocol IconFetching: Sendable {
    func search(query: String, prefix: String?, limit: Int) async throws -> [IconSearchResult]
    func fetch(id: String) async throws -> IconAsset
}

protocol IconNetworking: Sendable {
    func get(_ url: URL) async throws -> (body: Data, status: Int)
}

struct URLSessionIconNetworking: IconNetworking {
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func get(_ url: URL) async throws -> (body: Data, status: Int) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Till/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
