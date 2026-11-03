import Foundation
import SwiftData
import Testing
@testable import Till

/// The label field was removed from the stored model (schema v2). A store written by the
/// v1 schema, labels included, must open through `makeContainer` with its chips intact.
@MainActor
@Suite struct MigrationTests {
    @Test func aVersionOneStoreWithLabelsOpensAndKeepsItsChips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("till-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("till.store")

        let id = UUID()
        let deadline = TestClock.at(2026, 11, 4, 9, 0)
        do {
            let v1 = Schema(versionedSchema: TillSchemaV1.self)
            let container = try ModelContainer(
                for: v1, configurations: [ModelConfiguration(schema: v1, url: url)])
            container.mainContext.insert(
                TillSchemaV1.ChipEntity(
                    id: id, iconId: "mdi:coffee", iconMonotone: true, label: "Old",
                    accentHex: "#6FCFFF", deadline: deadline, approachWindow: 1800, kind: "quick",
                    createdDate: TestClock.now))
            try container.mainContext.save()
        }

        let reopened = try TillPersistence.makeContainer(inMemory: false, storeURL: url)
        let chips = try reopened.mainContext.fetch(FetchDescriptor<ChipEntity>())
        let chip = try #require(chips.first)
        #expect(chips.count == 1)
        #expect(chip.id == id)
        #expect(chip.iconId == "mdi:coffee")
        #expect(chip.accentHex == "#6FCFFF")
        #expect(chip.deadline == deadline)
        #expect(chip.pausedAt == nil)
    }

    @Test func aFreshInstallStillWorks() throws {
        let container = try TillPersistence.makeContainer(inMemory: true)
        container.mainContext.insert(
            ChipEntity(
                iconId: "sf:timer", iconMonotone: true, accentHex: "#6FCFFF",
                deadline: TestClock.now.addingTimeInterval(600), approachWindow: 1800,
                kind: "quick", createdDate: TestClock.now))
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<ChipEntity>()).count == 1)
    }
}
