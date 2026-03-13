import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            TerminalContainerView()
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            // Auto-start sessions
            for session in store.sessions where session.autoStart {
                store.openTab(sessionID: session.id)
            }
        }
    }
}
