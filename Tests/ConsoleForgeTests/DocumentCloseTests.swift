import XCTest
@testable import ConsoleForge

/// Closing a document tab from the session that opened it.
///
/// `handleCloseTab` matched `$0.isTerminal`, so `--close --name` could never reach a
/// document: a session could open a file into the panel and then had no way to take it
/// back out. The opener is the natural owner — it is already recorded as `parentTabID`
/// when the document is opened — so that is who may close it.
///
/// Addressed by PATH rather than by name, matching `--open-document`. Document tab names
/// are basenames, and two `report.md` tabs from different directories are ordinary.
@MainActor
final class DocumentCloseTests: XCTestCase {

    private func tempFile(_ name: String = "note.md") throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cf-close-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try "# hello".write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    func testTheOpenerClosesTheDocumentItOpened() throws {
        let store = SessionStore(inMemory: true)
        let console = store.addSession()
        store.openTab(sessionID: console.id)
        let path = try tempFile()
        let doc = store.openDocumentTab(path: path, parentTabID: console.id)

        XCTAssertEqual(store.closeDocumentTab(path: path, openerTabID: console.id), .closed(doc))
        XCTAssertFalse(store.openTabIDs.contains(doc))
    }

    func testASessionCannotCloseADocumentItDidNotOpen() throws {
        let store = SessionStore(inMemory: true)
        var openerConfig = SessionConfiguration(); openerConfig.name = "Opener"
        var otherConfig = SessionConfiguration(); otherConfig.name = "Other"
        let opener = store.addSession(openerConfig)
        let other = store.addSession(otherConfig)
        store.openTab(sessionID: opener.id)
        store.openTab(sessionID: other.id)
        let path = try tempFile()
        let doc = store.openDocumentTab(path: path, parentTabID: opener.id)

        // A stray close from an unrelated session must not reach into another's panel.
        XCTAssertEqual(store.closeDocumentTab(path: path, openerTabID: other.id),
                       .notTheOpener(ownerName: "Opener"))
        XCTAssertTrue(store.openTabIDs.contains(doc), "the document must survive")
    }

    func testClosingADocumentNobodyOpenedSaysSoRatherThanSilentlyDoingNothing() throws {
        let store = SessionStore(inMemory: true)
        let console = store.addSession()
        store.openTab(sessionID: console.id)

        XCTAssertEqual(store.closeDocumentTab(path: try tempFile(), openerTabID: console.id),
                       .notOpen)
    }

    func testClosingADocumentLeavesTheConsoleSelectionAlone() throws {
        let store = SessionStore(inMemory: true)
        let console = store.addSession()
        store.openTab(sessionID: console.id)
        let path = try tempFile()
        _ = store.openDocumentTab(path: path, parentTabID: console.id)
        let activeBefore = store.activeTabID

        _ = store.closeDocumentTab(path: path, openerTabID: console.id)

        // The Phase B invariant: touching activeTabID unmounts the live terminal view.
        XCTAssertEqual(store.activeTabID, activeBefore)
    }

    func testATildePathAddressesTheSameDocument() throws {
        let store = SessionStore(inMemory: true)
        let console = store.addSession()
        store.openTab(sessionID: console.id)
        let home = NSHomeDirectory()
        let name = "cf-close-\(UUID().uuidString).md"
        let full = (home as NSString).appendingPathComponent(name)
        try "# hello".write(toFile: full, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: full) }

        let doc = store.openDocumentTab(path: full, parentTabID: console.id)
        // Opened by absolute path, closed by the tilde form the CLI may pass through.
        XCTAssertEqual(store.closeDocumentTab(path: "~/\(name)", openerTabID: console.id),
                       .closed(doc))
    }
}
