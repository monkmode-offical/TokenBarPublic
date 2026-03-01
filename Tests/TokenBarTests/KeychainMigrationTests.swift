import Testing
@testable import TokenBar

@Suite
struct KeychainMigrationTests {
    @Test
    func migrationListCoversKnownKeychainItems() {
        let items = Set(KeychainMigration.itemsToMigrate.map(\.label))
        let expected: Set<String> = [
            "com.tokenbar:codex-cookie",
            "com.tokenbar:claude-cookie",
            "com.tokenbar:cursor-cookie",
            "com.tokenbar:factory-cookie",
            "com.tokenbar:minimax-cookie",
            "com.tokenbar:minimax-api-token",
            "com.tokenbar:augment-cookie",
            "com.tokenbar:copilot-api-token",
            "com.tokenbar:zai-api-token",
            "com.tokenbar:synthetic-api-key",
        ]

        let missing = expected.subtracting(items)
        #expect(missing.isEmpty, "Missing migration entries: \(missing.sorted())")
    }
}
