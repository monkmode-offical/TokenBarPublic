import TokenBarCore
import Commander
import Foundation
import Testing
@testable import TokenBarCLI

@Suite
struct CLIEntryTests {
    @Test
    func effectiveArgvDefaultsToUsage() {
        #expect(TokenBarCLI.effectiveArgv([]) == ["usage"])
        #expect(TokenBarCLI.effectiveArgv(["--json"]) == ["usage", "--json"])
        #expect(TokenBarCLI.effectiveArgv(["usage", "--json"]) == ["usage", "--json"])
    }

    @Test
    func decodesFormatFromOptionsAndFlags() {
        let jsonOption = ParsedValues(positional: [], options: ["format": ["json"]], flags: [])
        #expect(TokenBarCLI._decodeFormatForTesting(from: jsonOption) == .json)

        let jsonFlag = ParsedValues(positional: [], options: [:], flags: ["json"])
        #expect(TokenBarCLI._decodeFormatForTesting(from: jsonFlag) == .json)

        let textDefault = ParsedValues(positional: [], options: [:], flags: [])
        #expect(TokenBarCLI._decodeFormatForTesting(from: textDefault) == .text)
    }

    @Test
    func providerSelectionPrefersOverride() {
        let selection = TokenBarCLI.providerSelection(rawOverride: "codex", enabled: [.claude, .gemini])
        #expect(selection.asList == [.codex])
    }

    @Test
    func normalizeVersionExtractsNumeric() {
        #expect(TokenBarCLI.normalizeVersion(raw: "codex 1.2.3 (build 4)") == "1.2.3")
        #expect(TokenBarCLI.normalizeVersion(raw: "  v2.0  ") == "2.0")
    }

    @Test
    func makeHeaderIncludesVersionWhenAvailable() {
        let header = TokenBarCLI.makeHeader(provider: .codex, version: "1.2.3", source: "cli")
        #expect(header.contains("Codex"))
        #expect(header.contains("1.2.3"))
        #expect(header.contains("cli"))
    }

    @Test
    func renderOpenAIWebDashboardTextIncludesSummary() {
        let event = CreditEvent(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            service: "codex",
            creditsUsed: 10)
        let snapshot = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: 45,
            creditEvents: [event],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        let text = TokenBarCLI.renderOpenAIWebDashboardText(snapshot)

        #expect(text.contains("Web session: user@example.com"))
        #expect(text.contains("Code review: 45% remaining"))
        #expect(text.contains("Web history: 1 events"))
    }

    @Test
    func mapsErrorsToExitCodes() {
        #expect(TokenBarCLI.mapError(CodexStatusProbeError.codexNotInstalled) == ExitCode(2))
        #expect(TokenBarCLI.mapError(CodexStatusProbeError.timedOut) == ExitCode(4))
        #expect(TokenBarCLI.mapError(UsageError.noRateLimitsFound) == ExitCode(3))
    }

    @Test
    func providerSelectionFallsBackToBothForPrimaryPair() {
        let selection = TokenBarCLI.providerSelection(rawOverride: nil, enabled: [.codex, .claude])
        switch selection {
        case .both:
            break
        default:
            #expect(Bool(false))
        }
    }

    @Test
    func providerSelectionFallsBackToCustomWhenNonPrimary() {
        let selection = TokenBarCLI.providerSelection(rawOverride: nil, enabled: [.codex, .gemini])
        switch selection {
        case let .custom(providers):
            #expect(providers == [.codex, .gemini])
        default:
            #expect(Bool(false))
        }
    }

    @Test
    func providerSelectionDefaultsToCodexWhenEmpty() {
        let selection = TokenBarCLI.providerSelection(rawOverride: nil, enabled: [])
        switch selection {
        case let .single(provider):
            #expect(provider == .codex)
        default:
            #expect(Bool(false))
        }
    }

    @Test
    func decodesSourceAndTimeoutOptions() throws {
        let signature = TokenBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--web-timeout", "45", "--source", "oauth"])
        #expect(TokenBarCLI._decodeWebTimeoutForTesting(from: parsed) == 45)
        #expect(TokenBarCLI._decodeSourceModeForTesting(from: parsed) == .oauth)

        let parsedWeb = try parser.parse(arguments: ["--web"])
        #expect(TokenBarCLI._decodeSourceModeForTesting(from: parsedWeb) == .web)
    }

    @Test
    func shouldUseColorRespectsFormatAndFlags() {
        #expect(!TokenBarCLI.shouldUseColor(noColor: true, format: .text))
        #expect(!TokenBarCLI.shouldUseColor(noColor: false, format: .json))
    }
}
