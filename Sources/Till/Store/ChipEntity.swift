import Foundation
import SwiftData

/// Schema v1 (addendum A1.3): the original model, with an optional `label`. Kept only so
/// v1 stores migrate; nothing else uses it.
enum TillSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ChipEntity.self] }

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
    }
}

/// Schema v2 (operator decision 2026-11-03): chips have no label; the icon is the subject.
/// The one persisted model (design §7.4). Done deletes the row; `acknowledgedAt` and
/// `eventIdentifier` are schema-reserved and never written.
enum TillSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ChipEntity.self] }

    @Model
    final class ChipEntity {
        var id: UUID
        var iconId: String
        var iconMonotone: Bool
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
            id: UUID = UUID(), iconId: String, iconMonotone: Bool,
            accentHex: String, deadline: Date, approachWindow: TimeInterval, kind: String,
            createdDate: Date
        ) {
            self.id = id
            self.iconId = iconId
            self.iconMonotone = iconMonotone
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
}

/// The current model, under the name the rest of the app uses.
typealias ChipEntity = TillSchemaV2.ChipEntity

/// v1 -> v2 only drops the optional `label` attribute: a lightweight stage.
enum TillMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TillSchemaV1.self, TillSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: TillSchemaV1.self, toVersion: TillSchemaV2.self)]
    }
}

enum TillPersistence {
    /// In-memory container with a unique name (tests), or an on-disk store at `storeURL`.
    static func makeContainer(inMemory: Bool, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TillSchemaV2.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else if inMemory {
            configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(
            for: schema, migrationPlan: TillMigrationPlan.self, configurations: [configuration])
    }
}
