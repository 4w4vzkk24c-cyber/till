import Foundation
import os

/// Maps a transport error to the most specific `IconError`, so the picker can say what
/// actually went wrong instead of one generic "couldn't reach" line.
enum IconFailure {
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
    ]
    private static let tlsCodes: Set<URLError.Code> = [
        .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
        .clientCertificateRejected, .clientCertificateRequired,
        .appTransportSecurityRequiresSecureConnection,
    ]

    static func classify(_ error: Error) -> IconError {
        if let icon = error as? IconError { return icon }
        guard let url = error as? URLError else { return .network }
        if offlineCodes.contains(url.code) { return .offline }
        if tlsCodes.contains(url.code) { return .tls }
        if url.code == .timedOut { return .timedOut }
        return .network
    }
}

/// Diagnostics for the icon service. Logs the operation, error domain and code, and HTTP
/// status only: never a query, label, icon id or URL (a `URLError`'s own description
/// carries the failing URL, so it is deliberately not used).
enum IconLog {
    static let logger = Logger(subsystem: "com.crossedkeys.till", category: "icons")

    static func describe(_ error: Error, operation: String) -> String {
        let ns = error as NSError
        return "\(operation) failed: \(ns.domain) \(ns.code)"
    }

    static func record(_ error: Error, operation: String) {
        let line = describe(error, operation: operation)
        logger.error("\(line, privacy: .public)")
    }

    /// Progress breadcrumb (counts and state names only, never query text or ids).
    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func recordStatus(_ status: Int, operation: String) {
        logger.error("\(operation, privacy: .public) status \(status, privacy: .public)")
    }
}
