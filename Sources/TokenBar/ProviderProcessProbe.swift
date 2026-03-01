import Foundation
import TokenBarCore

enum ProviderProcessProbe {
    private static let interpreterBasenames: Set<String> = [
        "bash",
        "bun",
        "deno",
        "fish",
        "node",
        "nodejs",
        "python",
        "python3",
        "ruby",
        "sh",
        "zsh",
    ]
    private static let launcherBasenames: Set<String> = [
        "npm",
        "npx",
        "pnpm",
        "yarn",
        "bunx",
        "uv",
        "uvx",
        "pipx",
        "poetry",
    ]

    static func runningProviders() async -> Set<UsageProvider> {
        await Task.detached(priority: .utility) {
            self.runningProvidersNow()
        }.value
    }

    static func runningProvidersNow() -> Set<UsageProvider> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        // Drain stdout before waiting to avoid pipe-buffer deadlocks on large process lists.
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        guard let output = String(data: outputData, encoding: .utf8) else { return [] }

        var providers: Set<UsageProvider> = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if self.lineContainsCommand(line, command: "codex") {
                providers.insert(.codex)
            }
            if self.lineContainsCommand(line, command: "claude") {
                providers.insert(.claude)
            }
            if self.lineContainsCommand(line, command: "gemini") {
                providers.insert(.gemini)
            }
        }
        return providers
    }

    private static func lineContainsCommand(_ line: String, command: String) -> Bool {
        let lower = line.lowercased()
        if self.matchesKnownAppBundle(in: lower, command: command) {
            return true
        }

        let tokens = line.split(whereSeparator: \.isWhitespace).prefix(8).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        guard let first = tokens.first else { return false }
        if self.tokenMatchesCommand(first, command: command) {
            return true
        }

        let firstBase = URL(fileURLWithPath: first).lastPathComponent.lowercased()
        if self.interpreterBasenames.contains(firstBase) || self.launcherBasenames.contains(firstBase),
           tokens.count > 1
        {
            for token in tokens.dropFirst() {
                if self.tokenMatchesCommand(token, command: command) {
                    return true
                }
            }
        }

        return false
    }

    private static func matchesKnownAppBundle(in line: String, command: String) -> Bool {
        switch command {
        case "codex":
            line.contains("/applications/codex.app/")
                || line.contains("/applications/chatgpt.app/")
                || line.contains("contents/resources/chatgpthelper")
        case "claude":
            line.contains("/applications/claude.app/")
        case "gemini":
            line.contains("/applications/gemini.app/")
        default:
            false
        }
    }

    private static func tokenMatchesCommand(_ token: String, command: String) -> Bool {
        guard !token.hasPrefix("-") else { return false }
        let normalizedToken = token.lowercased()
        // Ignore desktop app executables (for example, Codex.app helper processes).
        if normalizedToken.contains(".app/contents/") {
            return false
        }
        let basename = URL(fileURLWithPath: token).lastPathComponent.lowercased()
        if basename == command { return true }
        if basename.hasPrefix("\(command)-") { return true }
        if basename.hasPrefix("\(command).") { return true }
        return false
    }
}
