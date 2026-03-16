import Foundation

struct ProcessParams {
    let executable: String
    let args: [String]
    let environment: [String]?
    let workingDirectory: String
}

/// Resolves the user's login shell once at startup.
/// Instead of forking to read `env` (which crashes under hardened runtime),
/// we spawn the login shell via PTY and let it resolve PATH naturally.
class ShellEnvironment {
    static let shared = ShellEnvironment()

    /// The user's login shell (e.g. /bin/zsh)
    let shell: String

    private init() {
        // Read login shell from passwd entry, fallback to /bin/zsh
        let pw = getpwuid(getuid())
        if let shellPtr = pw?.pointee.pw_shell {
            self.shell = String(cString: shellPtr)
        } else {
            self.shell = "/bin/zsh"
        }
    }
}

struct ClaudeProcessBuilder {

    static func build(from config: SessionConfiguration) -> ProcessParams {
        let env = ShellEnvironment.shared

        // Build the claude command string with all arguments
        var parts: [String] = ["claude"]

        if let model = config.model, !model.isEmpty {
            parts.append(contentsOf: ["--model", shellQuote(model)])
        }

        if let mode = config.permissionMode {
            parts.append(contentsOf: ["--permission-mode", mode.rawValue])
        }

        if let effort = config.effortLevel, !effort.isEmpty {
            parts.append(contentsOf: ["--effort", effort])
        }

        if let prompt = config.systemPrompt, !prompt.isEmpty {
            parts.append(contentsOf: ["--system-prompt", shellQuote(prompt)])
        }

        if let prompt = config.appendSystemPrompt, !prompt.isEmpty {
            parts.append(contentsOf: ["--append-system-prompt", shellQuote(prompt)])
        }

        if let tools = config.allowedTools, !tools.isEmpty {
            parts.append("--allowedTools")
            parts.append(contentsOf: tools.map { shellQuote($0) })
        }

        if let tools = config.disallowedTools, !tools.isEmpty {
            parts.append("--disallowedTools")
            parts.append(contentsOf: tools.map { shellQuote($0) })
        }

        if let mcp = config.mcpConfigPath, !mcp.isEmpty {
            parts.append(contentsOf: ["--mcp-config", shellQuote(mcp)])
        }

        if config.continueSession {
            parts.append("--continue")
        }

        // Parse additional flags
        let extraFlags = config.additionalFlags
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        parts.append(contentsOf: extraFlags)

        // Initial prompt as positional argument (no -p flag, which would make it non-interactive)
        if let prompt = config.initialPrompt, !prompt.isEmpty {
            parts.append(shellQuote(prompt))
        }

        let workDir = (config.workingDirectory as NSString).expandingTildeInPath
        let command = parts.joined(separator: " ")

        // Spawn the user's login shell which will resolve PATH and run claude
        // Using -l for login shell (loads .zprofile/.zshrc), -i for interactive, -c for command
        return ProcessParams(
            executable: env.shell,
            args: ["-l", "-i", "-c", command],
            environment: nil,  // Let the login shell set up its own environment
            workingDirectory: workDir
        )
    }

    /// Shell-quote a string to safely embed in a command
    private static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        // If it contains no special characters, return as-is
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:@,"))
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return s
        }
        // Wrap in single quotes, escaping any existing single quotes
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
