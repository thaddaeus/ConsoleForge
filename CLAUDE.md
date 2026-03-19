# ConsoleForge

A native macOS app for managing multiple AI coding terminal sessions in tabs.

## Tech Stack
- Swift 5.9+ / SwiftUI (macOS 14+)
- SwiftTerm (SPM) for terminal emulation with PTY support
- posix_spawn + openpty for fork-safe process launching (hardened runtime compatible)

## Architecture
- **Models/**: Data types (SessionConfiguration, SessionFolder, SessionState)
- **Services/**: SessionStore (persistence + state), ClaudeProcessBuilder (CLI arg builder), PtyProcess (PTY management)
- **Views/**: SwiftUI views organized by feature (Sidebar, Terminal, SessionEditor, Settings)

## Development

Build and run locally:
```bash
swift build
swift run
```

Update the running app without a full release:
```bash
swift build -c release
cp .build/release/ConsoleForge build/ConsoleForge.app/Contents/MacOS/ConsoleForge
open build/ConsoleForge.app
```

## Releasing

**IMPORTANT: `scripts/build.sh` is the ONLY way to create a release.** Do not manually zip, sign, notarize, or upload. The script handles everything:

1. `swift build -c release`
2. Create `.app` bundle with Info.plist
3. Code sign with Developer ID (hardened runtime + timestamp + entitlements)
4. Verify signature
5. Create DMG with Applications symlink
6. Sign DMG
7. Submit to Apple for notarization (waits for approval)
8. Staple notarization ticket to DMG
9. *(with `--release`)* Create GitHub release and upload DMG

```bash
# Required env var (signing identity — see memory for value)
export DEV_ID_APPLICATION="Developer ID Application: ..."

# Build + sign + notarize (no publish)
./scripts/build.sh 0.5.0

# Build + sign + notarize + publish to GitHub Releases
./scripts/build.sh 0.5.0 --release --notes "Fix tab close crash"
```

**Never do any of these manually:**
- Do not `zip` the app bundle — releases are DMGs, not zips
- Do not `codesign` outside the script — the script ensures correct flags
- Do not `xcrun notarytool submit` outside the script — the script handles submission, waiting, and stapling
- Do not `gh release create` outside the script — use `--release`
- Do not skip any step for "quick" releases — every release must be signed AND notarized

## Key Design Decisions
- Terminal views are kept alive in a ZStack (hidden via AppKit isHidden) to preserve running processes when switching tabs
- Sessions persist to `~/Library/Application Support/ConsoleForge/sessions.json`
- PtyProcess uses posix_spawn (not forkpty) for hardened runtime compatibility
- Claude binary is resolved via common path search at startup, configurable in Settings (Cmd+,)
- Login shell (`zsh -l -c`) used to inherit user's PATH for running CLI tools

## Session Configuration Fields
- name, workingDirectory, model, permissionMode, effort
- systemPrompt, appendSystemPrompt, initialPrompt
- allowedTools, disallowedTools, mcpConfigPath
- additionalFlags (raw CLI flags, one per line)
- tabColorHex, tabIconName (SF Symbol), autoStart, continueSession, openInConsoleForge
