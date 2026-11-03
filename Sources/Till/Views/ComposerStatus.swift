import Foundation

/// The single status line under the composer. Precedence: error, then icon fetch, then
/// the editing note, then the parse echo.
enum ComposerStatus: Equatable {
    case error(String)
    case fetching
    case editing
    case echo(String)

    static func line(error: String?, fetching: Bool, editing: Bool, echo: String?) -> ComposerStatus? {
        if let error { return .error(error) }
        if fetching { return .fetching }
        if editing { return .editing }
        if let echo { return .echo(echo) }
        return nil
    }
}
