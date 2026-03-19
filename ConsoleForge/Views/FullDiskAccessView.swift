import SwiftUI

/// Checks whether the app has Full Disk Access by probing a TCC-protected path.
/// Returns true if access is granted or if the check is inconclusive (path doesn't exist).
func hasFullDiskAccess() -> Bool {
    // ~/Library/Mail is TCC-protected on macOS 10.14+; readable only with FDA
    let testPath = NSHomeDirectory() + "/Library/Mail"
    let readable = FileManager.default.isReadableFile(atPath: testPath)
    // If the directory doesn't exist (no Mail configured), skip the prompt
    let exists = FileManager.default.fileExists(atPath: testPath)
    return readable || !exists
}

struct FullDiskAccessView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("Grant Full Disk Access")
                    .font(.title)
                    .fontWeight(.bold)

                Text("ConsoleForge needs this to stop macOS from asking\npermission every time a terminal session reads your files.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Explanation
            VStack(alignment: .leading, spacing: 16) {
                explanationRow(
                    icon: "terminal",
                    title: "Why does this happen?",
                    body: "ConsoleForge runs terminal sessions that access files across your system. macOS treats each protected folder as a separate permission, so you get repeated prompts."
                )

                explanationRow(
                    icon: "checkmark.shield",
                    title: "What does Full Disk Access do?",
                    body: "It grants ConsoleForge the same file access that Terminal.app and iTerm2 have — no more per-folder popups. This is standard for all third-party terminal apps."
                )

                explanationRow(
                    icon: "lock.shield",
                    title: "Is this safe?",
                    body: "Full Disk Access only lets ConsoleForge read files when its terminal sessions need to. It does not grant access to any other app or send data anywhere."
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                Text("How to enable:")
                    .font(.headline)

                stepRow(number: 1, text: "Click \"Open System Settings\" below")
                stepRow(number: 2, text: "Click the + button and add ConsoleForge")
                stepRow(number: 3, text: "Toggle it on, then restart ConsoleForge")
            }
            .padding(24)

            // Buttons
            HStack(spacing: 12) {
                Button("Remind Me Later") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Open System Settings") {
                    // Deep link to Privacy & Security > Full Disk Access
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480)
        .background(.background)
    }

    private func explanationRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())

            Text(text)
                .font(.callout)
        }
    }
}
