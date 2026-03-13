# ClaudeConnect

A native macOS app for managing multiple Claude Code CLI sessions in tabs, inspired by mRemoteNG.

## Tech Stack
- Swift 5.9+ / SwiftUI (macOS 14+)
- SwiftTerm (SPM) for terminal emulation with PTY support
- NSViewRepresentable bridge for SwiftTerm's AppKit LocalProcessTerminalView

## Architecture
- **Models/**: Data types (SessionConfiguration, SessionFolder, SessionState)
- **Services/**: SessionStore (persistence + state), ClaudeProcessBuilder (CLI arg builder)
- **Views/**: SwiftUI views organized by feature (Sidebar, Terminal, SessionEditor)

## Build & Run
```bash
swift build
swift run
```

## Key Design Decisions
- Terminal views are kept alive in a ZStack (hidden with opacity) to preserve running processes when switching tabs
- Sessions persist to `~/Library/Application Support/ClaudeConnect/sessions.json`
- SwiftTerm's LocalProcessTerminalView handles PTY lifecycle (fork, exec, signal handling)
- Claude binary is resolved via common paths + `which claude` fallback

## Session Configuration Fields
- name, workingDirectory, model, permissionMode, effort
- systemPrompt, appendSystemPrompt, initialPrompt
- allowedTools, disallowedTools, mcpConfigPath
- additionalFlags (raw CLI flags, one per line)
- tabColorHex, tabIconName (SF Symbol), autoStart, continueSession
