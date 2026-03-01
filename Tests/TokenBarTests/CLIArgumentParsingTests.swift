import TokenBarCore
import Commander
import Testing
@testable import TokenBarCLI

@Suite
struct CLIArgumentParsingTests {
    @Test
    func jsonShortcutDoesNotEnableJsonLogs() throws {
        let signature = TokenBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json"])

        #expect(parsed.flags.contains("jsonShortcut"))
        #expect(!parsed.flags.contains("jsonOutput"))
        #expect(TokenBarCLI._decodeFormatForTesting(from: parsed) == .json)
    }

    @Test
    func jsonOutputFlagEnablesJsonLogs() throws {
        let signature = TokenBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json-output"])

        #expect(parsed.flags.contains("jsonOutput"))
        #expect(!parsed.flags.contains("jsonShortcut"))
        #expect(TokenBarCLI._decodeFormatForTesting(from: parsed) == .text)
    }

    @Test
    func logLevelAndVerboseAreParsed() throws {
        let signature = TokenBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--log-level", "info", "--verbose"])

        #expect(parsed.flags.contains("verbose"))
        #expect(parsed.options["logLevel"] == ["info"])
    }

    @Test
    func resolvedLogLevelDefaultsToError() {
        #expect(TokenBarCLI.resolvedLogLevel(verbose: false, rawLevel: nil) == .error)
        #expect(TokenBarCLI.resolvedLogLevel(verbose: true, rawLevel: nil) == .debug)
        #expect(TokenBarCLI.resolvedLogLevel(verbose: false, rawLevel: "info") == .info)
    }

    @Test
    func formatOptionOverridesJsonShortcut() throws {
        let signature = TokenBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json", "--format", "text"])

        #expect(parsed.flags.contains("jsonShortcut"))
        #expect(parsed.options["format"] == ["text"])
        #expect(TokenBarCLI._decodeFormatForTesting(from: parsed) == .text)
    }

    @Test
    func jsonOnlyEnablesJsonFormat() throws {
        let signature = TokenBarCLI._usageSignatureForTesting()
        let parser = CommandParser(signature: signature)
        let parsed = try parser.parse(arguments: ["--json-only"])

        #expect(parsed.flags.contains("jsonOnly"))
        #expect(!parsed.flags.contains("jsonOutput"))
        #expect(TokenBarCLI._decodeFormatForTesting(from: parsed) == .json)
    }
}
