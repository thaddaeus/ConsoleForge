import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag & Drop Transfer

extension UTType {
    static let consoleForgeSession = UTType(exportedAs: "com.thaddaeus.consoleforge.session")
}

struct SessionTransfer: Codable, Transferable {
    let sessionID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .consoleForgeSession)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Environment(TabActivityTracker.self) private var activityTracker
    @Environment(\.openWindow) private var openWindow
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renamingFolderID: UUID?
    @State private var renameFolderName = ""
    @State private var hoveredSessionID: UUID?
    @State private var dropTargetFolderID: UUID?

    var body: some View {
        List {
            ForEach(store.folders) { folder in
                folderSection(folder)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .onTapGesture {
            // Resign terminal first responder so text fields can receive input
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let session = store.addSession()
                    store.editingSessionID = session.id
                    openWindow(id: "session-editor")
                } label: {
                    Label("New Session", systemImage: "plus")
                }

                Button {
                    showNewFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if !newFolderName.isEmpty {
                    store.addFolder(name: newFolderName)
                    newFolderName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renamingFolderID != nil },
            set: { if !$0 { renamingFolderID = nil } }
        )) {
            TextField("Folder name", text: $renameFolderName)
            Button("Rename") {
                if let id = renamingFolderID, !renameFolderName.isEmpty {
                    store.renameFolder(id: id, name: renameFolderName)
                }
                renamingFolderID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingFolderID = nil
            }
        }
    }

    @ViewBuilder
    private func folderSection(_ folder: SessionFolder) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { folder.isExpanded },
                set: { _ in store.toggleFolder(id: folder.id) }
            )
        ) {
            let folderSessions = store.sessionsInFolder(folder.id)
            ForEach(folderSessions) { session in
                sessionRow(session)
                    .draggable(SessionTransfer(sessionID: session.id.uuidString))
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                    .fontWeight(.medium)
                Spacer()
                Text("\(store.sessionsInFolder(folder.id).count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(dropTargetFolderID == folder.id ? Color.accentColor.opacity(0.2) : .clear)
            )
            .dropDestination(for: SessionTransfer.self) { items, _ in
                guard let item = items.first,
                      let sessionID = UUID(uuidString: item.sessionID) else { return false }
                store.moveSession(id: sessionID, toFolder: folder.id)
                return true
            } isTargeted: { targeted in
                dropTargetFolderID = targeted ? folder.id : (dropTargetFolderID == folder.id ? nil : dropTargetFolderID)
            }
            .contextMenu {
                Button("Rename...") {
                    renameFolderName = folder.name
                    renamingFolderID = folder.id
                }
                if folder.id != store.folders.first?.id {
                    Divider()
                    Button("Delete Folder", role: .destructive) {
                        store.deleteFolder(id: folder.id)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: SessionConfiguration) -> some View {
        let isHovered = hoveredSessionID == session.id
        return HStack(spacing: 8) {
            Circle()
                .fill(session.tabColor)
                .frame(width: 8, height: 8)

            Image(systemName: session.tabIconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(session.name)
                .lineLimit(1)

            Spacer()

            if store.openTabIDs.contains(session.id) {
                Circle()
                    .fill(activityTracker.activity(for: session.id).indicatorColor)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .onHover { hovering in
            hoveredSessionID = hovering ? session.id : nil
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            store.openTab(sessionID: session.id)
        }
        .contextMenu {
            Button("Open") {
                store.openTab(sessionID: session.id)
            }
            Button("Edit...") {
                store.editingSessionID = session.id
                openWindow(id: "session-editor")
            }
            Button("Duplicate") {
                store.duplicateSession(id: session.id)
            }
            Divider()
            Menu("Move to Folder") {
                ForEach(store.folders) { folder in
                    if folder.id != session.folderID {
                        Button(folder.name) {
                            store.moveSession(id: session.id, toFolder: folder.id)
                        }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.deleteSession(id: session.id)
            }
        }
    }
}
