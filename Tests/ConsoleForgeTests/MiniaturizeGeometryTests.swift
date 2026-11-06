import Testing
import CoreGraphics
@testable import ConsoleForge

/// Minimize → restore used to leave the console garbled until the window was literally
/// resized by hand. A miniaturized window keeps posting frame changes, and those bounds
/// describe the Dock teardown, not the terminal area: small, but above the degenerate
/// floor `setSize` rejects, so they were applied and SwiftTerm reflowed the buffer to a
/// width nothing had been written at. That is MODEL corruption (tasks 9543 / 9487), so
/// nothing on restore could repaint it away — only the next real resize rewrote it.
///
/// These assert the suspension itself, which is where the fix lives. Reverting
/// `isMiniaturized` out of `setSize` fails the first three.
@MainActor
struct MiniaturizeGeometryTests {
    /// A session-free manager: `setSize` / `resync` touch `sessions` only to iterate it,
    /// so the geometry decisions are observable with none open.
    private func manager(startingAt size: CGSize) -> TerminalSessionManager {
        let manager = TerminalSessionManager()
        manager.resync(to: size)   // synchronous, unlike the debounced setSize
        return manager
    }

    private let good = CGSize(width: 1200, height: 800)
    /// Big enough to pass `TerminalMetrics.isUsable`, far too narrow to be the real
    /// terminal area — the shape of what the Dock transition reports.
    private let dockTile = CGSize(width: 620, height: 300)

    /// Awaits the debounce rather than asserting straight after the call: `setSize`
    /// coalesces, so an immediate check passes whether or not the size is suspended
    /// and proves nothing. (Verified — asserting immediately passes with the fix
    /// reverted.)
    @Test func geometryWhileMiniaturizedIsIgnored() async throws {
        let manager = manager(startingAt: good)
        manager.windowDidMiniaturize()

        manager.setSize(dockTile)
        try await Task.sleep(for: .milliseconds(400))

        #expect(manager.currentSize == good)
    }

    @Test func resyncWhileMiniaturizedIsIgnored() {
        let manager = manager(startingAt: good)
        manager.windowDidMiniaturize()

        manager.resync(to: dockTile)

        #expect(manager.currentSize == good)
    }

    /// The debounce is the subtle half: a burst in flight when the window miniaturizes
    /// would otherwise fire ~140ms later and apply a size from before the transition.
    @Test func inFlightResizeBurstIsDroppedOnMiniaturize() async throws {
        let manager = manager(startingAt: good)
        manager.setSize(dockTile)      // queued, not yet applied
        manager.windowDidMiniaturize() // must cancel it

        try await Task.sleep(for: .milliseconds(400))

        #expect(manager.currentSize == good)
    }

    @Test func restoreAcceptsGeometryAgain() {
        let manager = manager(startingAt: dockTile)
        manager.windowDidMiniaturize()
        manager.windowDidDeminiaturize()

        manager.resync(to: good)

        #expect(manager.currentSize == good)
        #expect(manager.isMiniaturized == false)
    }

    /// Restore does not carry a size — the bounds at deminiaturize are mid-animation,
    /// so the host polls for them to settle and resyncs then.
    @Test func restoreDoesNotItselfChangeTheSize() {
        let manager = manager(startingAt: good)
        manager.windowDidMiniaturize()
        manager.windowDidDeminiaturize()

        #expect(manager.currentSize == good)
    }

    @Test func repeatedNotificationsAreIdempotent() {
        let manager = manager(startingAt: good)
        manager.windowDidDeminiaturize()  // never minimized — no-op
        #expect(manager.isMiniaturized == false)

        manager.windowDidMiniaturize()
        manager.windowDidMiniaturize()
        #expect(manager.isMiniaturized == true)

        manager.windowDidDeminiaturize()
        manager.windowDidDeminiaturize()
        #expect(manager.isMiniaturized == false)
    }
}
