import SwiftUI

@main
struct ClaudeConnectApp: App {
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    let session = store.addSession()
                    store.openTab(sessionID: session.id)
                }
                .keyboardShortcut("n")

                Button("New Folder") {
                    store.addFolder(name: "New Folder")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("Close Tab") {
                    if let active = store.activeTabID {
                        store.closeTab(sessionID: active)
                    }
                }
                .keyboardShortcut("w")
                .disabled(store.activeTabID == nil)

                Divider()

                Button("Next Tab") {
                    store.nextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Previous Tab") {
                    store.previousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                ForEach(0..<9, id: \.self) { index in
                    Button("Tab \(index + 1)") {
                        store.switchTabByIndex(index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(index >= store.openTabIDs.count)
                }
            }
        }
    }
}
