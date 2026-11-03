import Foundation
import SwiftData

/// The one persisted model (design §7.4). Done deletes the row; `acknowledgedAt` and
/// `eventIdentifier` are schema-reserved and never written in v1.
@Model
final class ChipEntity {
    var id: UUID
    var iconId: String
    var iconMonotone: Bool
    var label: String?
    var accentHex: String
    var deadline: Date
    var approachWindow: TimeInterval
    var kind: String
    var createdDate: Date
    var acknowledgedAt: Date?
    var pausedAt: Date?
    /// Set only when a delivery is actually observed (delegate interaction or
    /// reconciliation seeing delivered state) — never at scheduling (design §7.4, FEAS-01).
    var zeroCrossingHandled: Bool
    var eventIdentifier: String?

    init(
        id: UUID = UUID(), iconId: String, iconMonotone: Bool, label: String?,
        accentHex: String, deadline: Date, approachWindow: TimeInterval, kind: String,
        createdDate: Date
    ) {
        self.id = id
        self.iconId = iconId
        self.iconMonotone = iconMonotone
        self.label = label
        self.accentHex = accentHex
        self.deadline = deadline
        self.approachWindow = approachWindow
        self.kind = kind
        self.createdDate = createdDate
        self.acknowledgedAt = nil
        self.pausedAt = nil
        self.zeroCrossingHandled = false
        self.eventIdentifier = nil
    }

    var snapshot: ChipSnapshot {
        ChipSnapshot(id: id, deadline: deadline, pausedAt: pausedAt, approachWindow: approachWindow)
    }
}

/// Schema v1 (addendum A1.3). No migration yet; declared so a later plan has a baseline.
enum TillSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ChipEntity.self] }
}

enum TillPersistence {
    /// In-memory container with a unique name (tests), or an on-disk store at `storeURL`.
    static func makeContainer(inMemory: Bool, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TillSchemaV1.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else if inMemory {
            configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
