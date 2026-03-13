import Foundation

struct ProcessParams {
    let executable: String
    let args: [String]
    let environment: [String]?
    let workingDirectory: String
}

struct ClaudeProcessBuilder {
    static func resolveClaudePath() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "/opt/homebrew/bin/claude",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try `which claude` via shell
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}

        return nil
    }

    static func build(from config: SessionConfiguration) -> ProcessParams {
        let claudePath = resolveClaudePath() ?? "claude"

        var args: [String] = []

        if let model = config.model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }

        if let mode = config.permissionMode {
            args.append(contentsOf: ["--permission-mode", mode.rawValue])
        }

        if let effort = config.effortLevel, !effort.isEmpty {
            args.append(contentsOf: ["--effort", effort])
        }

        if let prompt = config.systemPrompt, !prompt.isEmpty {
            args.append(contentsOf: ["--system-prompt", prompt])
        }

        if let prompt = config.appendSystemPrompt, !prompt.isEmpty {
            args.append(contentsOf: ["--append-system-prompt", prompt])
        }

        if let tools = config.allowedTools, !tools.isEmpty {
            args.append("--allowedTools")
            args.append(contentsOf: tools)
        }

        if let tools = config.disallowedTools, !tools.isEmpty {
            args.append("--disallowedTools")
            args.append(contentsOf: tools)
        }

        if let mcp = config.mcpConfigPath, !mcp.isEmpty {
            args.append(contentsOf: ["--mcp-config", mcp])
        }

        if config.continueSession {
            args.append("--continue")
        }

        // Parse additional flags
        let extraFlags = config.additionalFlags
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        args.append(contentsOf: extraFlags)

        // Initial prompt as positional argument
        if let prompt = config.initialPrompt, !prompt.isEmpty {
            args.append("-p")
            args.append(prompt)
        }

        let workDir = (config.workingDirectory as NSString).expandingTildeInPath

        return ProcessParams(
            executable: claudePath,
            args: args,
            environment: nil,
            workingDirectory: workDir
        )
    }
}
