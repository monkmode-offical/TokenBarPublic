import Foundation
import Testing
import TokenBarCore
@testable import TokenBar

private final class CountingTokenStore: ZaiTokenStoring, SyntheticTokenStoring, CopilotTokenStoring, KimiTokenStoring,
    KimiK2TokenStoring, MiniMaxAPITokenStoring, @unchecked Sendable
{
    var value: String?
    var loadCalls = 0

    init(value: String? = nil) {
        self.value = value
    }

    func loadToken() throws -> String? {
        self.loadCalls += 1
        return self.value
    }

    func storeToken(_ token: String?) throws {
        self.value = token
    }
}

private final class CountingCookieStore: CookieHeaderStoring, MiniMaxCookieStoring, @unchecked Sendable {
    var value: String?
    var loadCalls = 0

    init(value: String? = nil) {
        self.value = value
    }

    func loadCookieHeader() throws -> String? {
        self.loadCalls += 1
        return self.value
    }

    func storeCookieHeader(_ header: String?) throws {
        self.value = header
    }
}

private final class CountingTokenAccountStore: ProviderTokenAccountStoring, @unchecked Sendable {
    var accounts: [UsageProvider: ProviderTokenAccountData]
    var loadCalls = 0
    private let fileURL: URL

    init(accounts: [UsageProvider: ProviderTokenAccountData]) {
        self.accounts = accounts
        self.fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenbar-accounts-\(UUID().uuidString).json")
    }

    func loadAccounts() throws -> [UsageProvider: ProviderTokenAccountData] {
        self.loadCalls += 1
        return self.accounts
    }

    func storeAccounts(_ accounts: [UsageProvider: ProviderTokenAccountData]) throws {
        self.accounts = accounts
    }

    func ensureFileExists() throws -> URL {
        self.fileURL
    }
}

private struct CountingLegacyStores {
    let zai = CountingTokenStore(value: "zai-token")
    let synthetic = CountingTokenStore(value: "synthetic-token")
    let codex = CountingCookieStore(value: "codex-cookie")
    let claude = CountingCookieStore(value: "claude-cookie")
    let cursor = CountingCookieStore(value: "cursor-cookie")
    let opencode = CountingCookieStore(value: "opencode-cookie")
    let factory = CountingCookieStore(value: "factory-cookie")
    let minimaxCookie = CountingCookieStore(value: "minimax-cookie")
    let minimaxToken = CountingTokenStore(value: "minimax-token")
    let kimi = CountingTokenStore(value: "kimi-token")
    let kimiK2 = CountingTokenStore(value: "kimi-k2-token")
    let augment = CountingCookieStore(value: "augment-cookie")
    let amp = CountingCookieStore(value: "amp-cookie")
    let copilot = CountingTokenStore(value: "copilot-token")
    let tokenAccounts: CountingTokenAccountStore

    init() {
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Legacy",
            token: "legacy-token",
            addedAt: Date().timeIntervalSince1970,
            lastUsed: nil)
        let accountData = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)
        self.tokenAccounts = CountingTokenAccountStore(accounts: [.claude: accountData])
    }

    var legacyStores: TokenBarConfigMigrator.LegacyStores {
        TokenBarConfigMigrator.LegacyStores(
            zaiTokenStore: self.zai,
            syntheticTokenStore: self.synthetic,
            codexCookieStore: self.codex,
            claudeCookieStore: self.claude,
            cursorCookieStore: self.cursor,
            opencodeCookieStore: self.opencode,
            factoryCookieStore: self.factory,
            minimaxCookieStore: self.minimaxCookie,
            minimaxAPITokenStore: self.minimaxToken,
            kimiTokenStore: self.kimi,
            kimiK2TokenStore: self.kimiK2,
            augmentCookieStore: self.augment,
            ampCookieStore: self.amp,
            copilotTokenStore: self.copilot,
            tokenAccountStore: self.tokenAccounts)
    }

    var totalLoadCalls: Int {
        self.zai.loadCalls
            + self.synthetic.loadCalls
            + self.codex.loadCalls
            + self.claude.loadCalls
            + self.cursor.loadCalls
            + self.opencode.loadCalls
            + self.factory.loadCalls
            + self.minimaxCookie.loadCalls
            + self.minimaxToken.loadCalls
            + self.kimi.loadCalls
            + self.kimiK2.loadCalls
            + self.augment.loadCalls
            + self.amp.loadCalls
            + self.copilot.loadCalls
            + self.tokenAccounts.loadCalls
    }
}

@Suite
struct TokenBarConfigMigratorTests {
    @Test
    func legacyKeychainMigrationIsAttemptedOnlyOnce() throws {
        let suite = "TokenBarConfigMigratorTests-once"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let firstStores = CountingLegacyStores()
        let firstConfig = TokenBarConfigMigrator.loadOrMigrate(
            configStore: configStore,
            userDefaults: defaults,
            stores: firstStores.legacyStores)

        #expect(firstStores.totalLoadCalls > 0)
        #expect(firstConfig.providerConfig(for: .zai)?.apiKey == "zai-token")
        #expect(firstConfig.providerConfig(for: .codex)?.cookieHeader == "codex-cookie")
        #expect(firstConfig.providerConfig(for: .claude)?.tokenAccounts?.accounts.count == 1)

        let secondStores = CountingLegacyStores()
        _ = TokenBarConfigMigrator.loadOrMigrate(
            configStore: configStore,
            userDefaults: defaults,
            stores: secondStores.legacyStores)

        #expect(secondStores.totalLoadCalls == 0)
    }
}
