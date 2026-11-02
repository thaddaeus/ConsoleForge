import SwiftUI
import SwiftTerm

/// Debug toggles. Enable geometry tracing with:
///   defaults write <bundle-id> CFDebugGeometry -bool YES
/// (read once at launch — relaunch to change). When on, the resize pipeline logs the
/// triple `container px → SwiftTerm cols×rows → PTY winsize` so a row/height desync is
/// provable rather than eyeballed. See task 9528.
enum CFDebug {
    static let geometry = UserDefaults.standard.bool(forKey: "CFDebugGeometry")
}

/// Retains one `TerminalSession` per open tab, independent of the view hierarchy.
/// Only the active session's view is mounted (see `TerminalHostView`); the rest
/// keep running detached. The manager creates/destroys sessions in `reconcile`
/// to track the set of open tabs.
@MainActor
@Observable
final class TerminalSessionManager {
    private(set) var sessions: [UUID: TerminalSession] = [:]

    /// The live terminal-area size. New sessions are born at this size and all
    /// existing sessions are resized to it, so a tab is never reflowed from a stale
    /// placeholder size on first mount (which corrupts the SwiftTerm buffer model).
    private(set) var currentSize = CGSize(width: 800, height: 600)

    /// Backing scale of the display the terminal is on, kept in sync by
    /// `TerminalContainerView`. Since SwiftTerm v1.16.0 the cell width snaps to the
    /// nearest DEVICE pixel, so Menlo 11 is 6.5pt at 2x and 7.0pt at 1x — every
    /// columns-from-points judgement below has to be made against the screen the
    /// window is actually on, or the degenerate-geometry floor is measured in cells
    /// that do not exist there.
    var displayScale: CGFloat = TerminalMetrics.defaultScale

    /// True once a real size has been applied. Sessions are created off the back of
    /// this (see `TerminalContainerView.reconcile`), so it deliberately flips on the
    /// SETTLED size, not the first one seen.
    private(set) var hasAppliedRealSize = false
    /// Latest size seen during an in-flight resize burst; applied when the trailing
    /// debounce fires.
    private var pendingSize: CGSize?
    private var resizeDebounce: Task<Void, Never>?
    private var settleNudge: Task<Void, Never>?
    /// Intermediate sizes swallowed since the last apply, for CFDebugGeometry.
    private var coalescedCount = 0

    /// True while the window is in the Dock. A miniaturized window keeps reporting
    /// frame changes, and those bounds are NOT the terminal area — they are whatever
    /// AppKit leaves behind while it tears the window's surface down for the Dock tile.
    /// They are small but often still above the degenerate floor, so `setSize`'s guard
    /// waved them through and SwiftTerm reflowed the buffer to a width nothing was
    /// written at. That is the minimize→restore garble, and it is MODEL corruption, so
    /// no amount of repainting on restore fixes it — only the next real window resize,
    /// which is exactly what Tadd had to do. The cure is to not reflow in the first
    /// place: while this is set, geometry is ignored outright, and restore re-asserts
    /// the true bounds through `resync` once they settle.
    private(set) var isMiniaturized = false

    /// Trailing debounce for resize bursts. The animated fullscreen enter/exit
    /// (~0.5s) fires frameDidChange at many intermediate sizes; reflowing SwiftTerm
    /// and SIGWINCHing the PTY at each one makes Claude redraw its bottom-anchored
    /// TUI at several wrong widths (transient garble + orphaned prompt lines in
    /// scrollback). Only the final geometry should reach the terminal (task 9543).
    private static let debounceInterval: Duration = .milliseconds(140)
    /// Delay after the final geometry lands before re-delivering SIGWINCH, so the
    /// nudge arrives after the transition (and the child's own resize handling)
    /// has settled.
    private static let nudgeDelay: Duration = .milliseconds(300)

    func session(for id: UUID?) -> TerminalSession? {
        guard let id else { return nil }
        return sessions[id]
    }

    /// Update the live terminal-area size and keep every session (active + detached)
    /// in lockstep. Call this before `reconcile` so newly created sessions start at
    /// the real size rather than the placeholder.
    ///
    /// The first real size applies synchronously; later sizes are coalesced with a
    /// trailing debounce so a burst of intermediate geometries (animated fullscreen
    /// transition, live window drag) produces exactly one SwiftTerm reflow + PTY
    /// winsize at the final size.
    func setSize(_ size: CGSize) {
        // Nothing the window reports from the Dock describes the terminal area. Drop
        // it, and drop any burst already in flight with it — a debounce that fires
        // after the window miniaturizes would apply a pre-minimize intermediate.
        guard !isMiniaturized else {
            GeometryTrace.shared.record("ignored",
                "container=\(Int(size.width))×\(Int(size.height)) — window miniaturized")
            resizeDebounce?.cancel()
            resizeDebounce = nil
            pendingSize = nil
            coalescedCount = 0
            return
        }
        // A degenerate geometry is REJECTED outright, not clamped and not applied. The
        // old `> 1` test let a ~27pt container through as a two-column grid, and a
        // resumed session flooding its history in at two columns re-breaks every
        // wrapped line permanently — widening again cannot undo it. Anything this
        // small is a container mid-collapse or mid-transition, so the last good size
        // is the correct thing to keep.
        guard TerminalMetrics.isUsable(size, scale: displayScale) else {
            GeometryTrace.shared.record("rejected",
                "container=\(Int(size.width))×\(Int(size.height)) " +
                "(\(TerminalMetrics.columns(forWidth: size.width, scale: displayScale)) cols) — keeping " +
                "\(Int(currentSize.width))×\(Int(currentSize.height))")
            if CFDebug.geometry {
                print("[geom] REJECTED degenerate container=\(Int(size.width))×\(Int(size.height))")
            }
            return
        }
        GeometryTrace.shared.noteContainer(size)
        GeometryTrace.shared.record("setSize",
            "container=\(Int(size.width))×\(Int(size.height)) " +
            "(\(TerminalMetrics.columns(forWidth: size.width, scale: displayScale)) cols) → debounce")
        // EVERY size is debounced, the first one included. It used to land
        // synchronously so sessions were born at a real size rather than the 800×600
        // placeholder (task 9528) — but the trace showed the window has not settled by
        // then: launch emitted 544×740, then 781×874, so a session was born at 75
        // columns and immediately reflowed to 109. Harmless for an empty buffer,
        // corrupting for a resumed one flooding its history in between. Waiting one
        // debounce is strictly better: still never the placeholder, and now never a
        // transient either.
        pendingSize = size
        coalescedCount += 1
        resizeDebounce?.cancel()
        resizeDebounce = Task { [weak self] in
            do { try await Task.sleep(for: Self.debounceInterval) } catch { return }
            guard let self else { return }
            self.resizeDebounce = nil
            if let pending = self.pendingSize, pending != self.currentSize {
                self.applySize(pending)
            }
            self.pendingSize = nil
            self.coalescedCount = 0
        }
    }

    private func applySize(_ size: CGSize) {
        hasAppliedRealSize = true
        GeometryTrace.shared.record("applied",
            "container=\(Int(size.width))×\(Int(size.height)) sessions=\(sessions.count) coalesced=\(coalescedCount)")
        currentSize = size
        if CFDebug.geometry {
            print("[geom] setSize container=\(Int(size.width))×\(Int(size.height)) sessions=\(sessions.count) coalesced=\(coalescedCount)")
        }
        coalescedCount = 0
        for session in sessions.values {
            session.resize(to: size)
        }
        scheduleSettleNudge()
    }

    /// After the final geometry lands and the transition settles, re-deliver
    /// SIGWINCH to each child (task 9543 part 2). A child that already handled the
    /// resize treats it as a no-op (node emits 'resize' only when the dimensions
    /// actually changed); a child that missed or raced the original signal repaints
    /// its idle prompt/status instead of staying garbled until the next output.
    private func scheduleSettleNudge() {
        settleNudge?.cancel()
        settleNudge = Task { [weak self] in
            do { try await Task.sleep(for: Self.nudgeDelay) } catch { return }
            guard let self else { return }
            self.settleNudge = nil
            for session in self.sessions.values {
                session.nudgeRedraw()
            }
        }
    }

    /// The window went to the Dock: stop accepting geometry until it comes back.
    func windowDidMiniaturize() {
        guard !isMiniaturized else { return }
        isMiniaturized = true
        resizeDebounce?.cancel()
        resizeDebounce = nil
        pendingSize = nil
        coalescedCount = 0
        // A settle nudge landing while minimized would jiggle the PTY for a window
        // nobody can see, and its restore repaint is `resync`'s job anyway.
        settleNudge?.cancel()
        settleNudge = nil
        GeometryTrace.shared.record("miniaturized", "geometry suspended")
    }

    /// The window came back from the Dock. Geometry is accepted again, but the caller
    /// does NOT hand us a size here — the bounds right at restore are still mid-flight.
    /// `TerminalHostView` polls for them to settle and then calls `resync`.
    func windowDidDeminiaturize() {
        guard isMiniaturized else { return }
        isMiniaturized = false
        GeometryTrace.shared.record("deminiaturized", "geometry resumed, awaiting settle")
    }

    /// Recover the grid after an event that can desync SwiftTerm + the PTY from the
    /// view WITHOUT a reliable frame change: display sleep/wake, an external display
    /// connecting/disconnecting, or a forced un-fullscreen. The trigger that exposed
    /// this: fullscreen on an external display, the Mac sleeps, the external is
    /// unplugged, and the lid opens to a windowed app on the built-in screen — the
    /// window geometry changes while asleep, and the wake/fullscreen observers only
    /// *repaint* (redrawing the stale layout), never re-assert the size or make Claude
    /// regenerate its output. So: re-assert the TRUE current size to every session,
    /// repaint from the buffer model, then (after the geometry settles) force each
    /// child to redraw its full TUI at the correct size — overwriting a corrupted or
    /// stale-width live region that a plain repaint can't fix. `size` is the
    /// container's real bounds, read at call time (not the possibly-stale cached size).
    func resync(to size: CGSize) {
        guard !isMiniaturized else { return }
        guard TerminalMetrics.isUsable(size, scale: displayScale) else { return }
        resizeDebounce?.cancel()
        resizeDebounce = nil
        pendingSize = nil
        if CFDebug.geometry {
            print("[geom] resync container=\(Int(size.width))×\(Int(size.height)) sessions=\(sessions.count)")
        }
        GeometryTrace.shared.record("resync", "container=\(Int(size.width))×\(Int(size.height))")
        currentSize = size
        for session in sessions.values {
            session.resize(to: size)   // re-assert frame → SwiftTerm reflow → PTY winsize (no-op if unchanged)
            session.forceFullRepaint() // redraw the rendered surface from the buffer model
        }
        // After AppKit settles the new geometry, force a full child redraw so an idle
        // Claude regenerates its bottom-anchored TUI at the correct width.
        settleNudge?.cancel()
        settleNudge = Task { [weak self] in
            do { try await Task.sleep(for: Self.nudgeDelay) } catch { return }
            guard let self else { return }
            self.settleNudge = nil
            for session in self.sessions.values {
                session.forceRedraw()
            }
        }
    }

    /// Bring the live session set in line with `openIDs`: shut down + drop any
    /// session whose id has left the open set, and create a session for any new
    /// id. `resolveLaunch` yields the launch config (with its pinned Claude
    /// session id) and whether to resume it; both flow into the new session.
    func reconcile(
        openIDs: [UUID],
        resolveLaunch: (UUID) -> (config: SessionConfiguration, resume: Bool)?,
        onOutput: @escaping (UUID) -> Void,
        onBell: @escaping (UUID) -> Void,
        onTerminated: @escaping (UUID, Int32?) -> Void
    ) {
        let openSet = Set(openIDs)

        // Drop sessions for tabs that are gone.
        for (id, session) in sessions where !openSet.contains(id) {
            session.shutdown()
            sessions.removeValue(forKey: id)
        }

        // Create sessions for newly opened tabs.
        for id in openIDs where sessions[id] == nil {
            guard let launch = resolveLaunch(id) else { continue }
            let session = TerminalSession(sessionID: id, configuration: launch.config, resume: launch.resume, initialSize: currentSize)
            wire(session, id: id, onOutput: onOutput, onBell: onBell, onTerminated: onTerminated)
            sessions[id] = session
        }
    }

    /// Tear down one session and recreate it (used by Restart). The replacement
    /// launches with the given config/resume (see `SessionStore.resolveLaunch`,
    /// which pins a fresh Claude session id for the restart) and re-wires callbacks.
    func restart(
        id: UUID,
        configuration: SessionConfiguration,
        resume: Bool = false,
        onOutput: @escaping (UUID) -> Void,
        onBell: @escaping (UUID) -> Void,
        onTerminated: @escaping (UUID, Int32?) -> Void
    ) {
        sessions[id]?.shutdown()
        let session = TerminalSession(sessionID: id, configuration: configuration, resume: resume, initialSize: currentSize)
        wire(session, id: id, onOutput: onOutput, onBell: onBell, onTerminated: onTerminated)
        sessions[id] = session
    }

    func shutdownAll() {
        resizeDebounce?.cancel()
        settleNudge?.cancel()
        for session in sessions.values {
            session.shutdown()
        }
        sessions.removeAll()
    }

    private func wire(
        _ session: TerminalSession,
        id: UUID,
        onOutput: @escaping (UUID) -> Void,
        onBell: @escaping (UUID) -> Void,
        onTerminated: @escaping (UUID, Int32?) -> Void
    ) {
        session.onOutputReceived = { onOutput(id) }
        session.onBellReceived = { onBell(id) }
        session.onProcessTerminated = { code in onTerminated(id, code) }
    }
}

/// Hosts a single (the active) `TerminalSession`'s `TerminalView` inside a
/// container NSView. Swapping `session` removes the previous terminal view
/// (calling `unmount`) and adds the new one (calling `mount`). Inactive
/// terminals stay detached but alive — owned by `TerminalSessionManager`.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession?
    /// Called with the live terminal-area size whenever the container's frame changes.
    /// The container's bounds always reflect the real area (window size, fullscreen
    /// mode, and sidebar width all flow through the view hierarchy to it), so this is
    /// the authoritative, AppKit-driven size source — wired to the manager's `setSize`.
    let onContainerResize: (CGSize) -> Void
    /// Called with the container's real bounds after a sleep/wake, display
    /// reconfiguration or Dock restore settles — wired to the manager's `resync`, which
    /// re-asserts the size and forces a redraw (a plain frame change isn't guaranteed
    /// across these events, and the existing repaint-only handlers can't fix a
    /// stale-width grid).
    let onResync: (CGSize) -> Void
    /// Called when the window miniaturizes / comes back — wired to the manager, which
    /// suspends geometry for the duration (see `TerminalSessionManager.isMiniaturized`).
    let onMiniaturize: () -> Void
    let onDeminiaturize: () -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        container.autoresizingMask = [.width, .height]
        // The terminal view's frame intentionally trails the container during a
        // resize burst (coalesced sizing, task 9543) — clip so an old-size terminal
        // can't paint outside the terminal area while the window is shrinking.
        container.clipsToBounds = true

        // The single source of truth for the terminal-area size. SwiftUI's
        // GeometryReader is unreliable across the animated fullscreen↔windowed
        // transition — it can fail to re-fire, leaving the grid's ROW count stale so
        // Claude's bottom-anchored input box overstrikes (task 9528). AppKit's
        // frameDidChange fires on every real geometry change, so we drive resize from
        // the container's actual bounds instead.
        container.postsFrameChangedNotifications = true
        context.coordinator.container = container
        context.coordinator.onResize = onContainerResize
        context.coordinator.onResync = onResync
        context.coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: container,
            queue: .main
        ) { [weak coordinator = context.coordinator] note in
            MainActor.assumeIsolated {
                guard let view = note.object as? NSView else { return }
                coordinator?.onResize?(view.bounds.size)
            }
        }

        // Display sleep/wake and screen reconfiguration (e.g. fullscreen on an
        // external display → sleep → unplug → lid open to a windowed app on the
        // built-in screen) change the window geometry while the app is asleep, so a
        // `frameDidChange` for the final size isn't guaranteed and the grid can be left
        // desynced. Re-read the TRUE bounds once AppKit settles and force a re-sync.
        //
        // "Settles" is now MEASURED, not assumed. This used to be a single shot 0.5s
        // after the notification, which is a guess about an interval nothing promises:
        // a wake with a display change behind it hands out bounds for well over a
        // second, so the one shot read a mid-flight size, resynced to it, and left the
        // grid wrong — the "still doesn't settle right from sleep" half of the bug. The
        // poller instead waits for two consecutive identical readings before it
        // resyncs, so it fires when the geometry has actually stopped moving.
        let resyncAfterSettle: @Sendable (Notification) -> Void = { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                coordinator?.scheduleResyncWhenSettled()
            }
        }
        context.coordinator.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: resyncAfterSettle
        )
        // System wake and DISPLAY wake are different notifications: locking the screen
        // or letting the display sleep on its own never posts `didWakeNotification`, so
        // that path had no recovery at all.
        context.coordinator.screensWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: resyncAfterSettle
        )
        context.coordinator.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: resyncAfterSettle
        )

        // Minimize / restore. The window is not observable yet (`container.window` is
        // nil until it joins a hierarchy), so these watch ALL windows and filter to
        // ours at fire time — the same shape as the occlusion observer in
        // `TerminalSession`. Restore does not pass a size: it starts the settle poller,
        // because the bounds at the moment of deminiaturize are still mid-animation.
        context.coordinator.onMiniaturize = onMiniaturize
        context.coordinator.onDeminiaturize = onDeminiaturize
        context.coordinator.miniaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main
        ) { [weak coordinator = context.coordinator] note in
            MainActor.assumeIsolated {
                guard let coordinator, coordinator.ownsWindow(in: note) else { return }
                coordinator.cancelSettlePoll()
                coordinator.onMiniaturize?()
            }
        }
        context.coordinator.deminiaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main
        ) { [weak coordinator = context.coordinator] note in
            MainActor.assumeIsolated {
                guard let coordinator, coordinator.ownsWindow(in: note) else { return }
                coordinator.onDeminiaturize?()
                coordinator.scheduleResyncWhenSettled()
            }
        }
        return container
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let obs = coordinator.frameObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        for obs in [coordinator.wakeObserver, coordinator.screensWakeObserver].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        for obs in [coordinator.screenObserver,
                    coordinator.miniaturizeObserver,
                    coordinator.deminiaturizeObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
        coordinator.cancelSettlePoll()
        coordinator.frameObserver = nil
        coordinator.wakeObserver = nil
        coordinator.screensWakeObserver = nil
        coordinator.screenObserver = nil
        coordinator.miniaturizeObserver = nil
        coordinator.deminiaturizeObserver = nil
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Keep the callbacks current (SwiftUI hands us fresh closures each pass).
        context.coordinator.onResize = onContainerResize
        context.coordinator.onResync = onResync
        context.coordinator.onMiniaturize = onMiniaturize
        context.coordinator.onDeminiaturize = onDeminiaturize

        let current = container.subviews.first as? TerminalView
        let target = session?.terminalView

        // Same view already mounted — nothing to do.
        if current === target { return }

        // Swap out the previous terminal (if any).
        if let current {
            // Find the session that owns the outgoing view to pause its link.
            context.coordinator.mountedSession?.unmount()
            current.removeFromSuperview()
        }
        context.coordinator.mountedSession = nil

        // Mount the new terminal. No autoresizing mask: AppKit would resize the
        // mounted view at every frame of an animated window transition, reflowing
        // SwiftTerm at each intermediate size and bypassing the manager's coalesced
        // setSize path — which is the single source of frame changes for mounted
        // and detached terminals alike (task 9543).
        if let session, let target {
            // The LAST unguarded frame write in the app, and the one that bit: mounting
            // into a container that is collapsed, zero-width or mid-transition would set
            // the terminal's frame directly here, reflowing the buffer to a couple of
            // columns and bypassing setSize's floor entirely. Adopt the container's
            // geometry only when it is a usable terminal size; otherwise leave the view
            // at the good size it already has and let the next real frameDidChange
            // correct it through the coalesced path.
            let scale = container.window?.backingScaleFactor ?? TerminalMetrics.defaultScale
            if TerminalMetrics.isUsable(container.bounds.size, scale: scale) {
                target.frame = container.bounds
            }
            target.autoresizingMask = []
            container.addSubview(target)
            context.coordinator.mountedSession = session
            session.mount()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        /// The session whose view is currently mounted, so we can call `unmount`
        /// on it when swapping (the outgoing view's owning session isn't always
        /// the new `session` value).
        var mountedSession: TerminalSession?
        /// The hosted container view, so the sleep/wake + screen observers can read its
        /// real bounds at fire time. Weak — AppKit owns it.
        weak var container: NSView?
        /// Latest resize callback (refreshed each `updateNSView`).
        var onResize: ((CGSize) -> Void)?
        /// Latest resync callback (refreshed each `updateNSView`).
        var onResync: ((CGSize) -> Void)?
        /// Latest miniaturize callbacks (refreshed each `updateNSView`).
        var onMiniaturize: (() -> Void)?
        var onDeminiaturize: (() -> Void)?
        /// Token for the container's frame-change observer, removed on dismantle.
        var frameObserver: NSObjectProtocol?
        /// Tokens for the sleep/wake + screen-reconfiguration observers.
        var wakeObserver: NSObjectProtocol?
        var screensWakeObserver: NSObjectProtocol?
        var screenObserver: NSObjectProtocol?
        /// Tokens for the Dock minimize/restore observers.
        var miniaturizeObserver: NSObjectProtocol?
        var deminiaturizeObserver: NSObjectProtocol?

        /// In-flight settle poll, so a second trigger (wake AND a screen change, which
        /// routinely arrive together) restarts the wait instead of racing itself.
        private var settlePoll: Task<Void, Never>?
        /// How often the poller samples the container's bounds.
        private static let settleInterval: Duration = .milliseconds(150)
        /// Give up waiting for stability after this long and resync to whatever is
        /// there. A geometry that never settles is a bug of its own, but leaving the
        /// grid desynced forever is worse than resyncing to a late reading.
        private static let settleTimeout: Duration = .seconds(3)

        /// True when `note`'s window is the one hosting our container.
        func ownsWindow(in note: Notification) -> Bool {
            guard let window = note.object as? NSWindow, let container else { return false }
            return window === container.window
        }

        /// Wait for the container's bounds to stop changing, then resync to them.
        /// Requires two consecutive identical, usable readings — one reading proves
        /// nothing, since every mid-flight size is also "a size".
        func scheduleResyncWhenSettled() {
            settlePoll?.cancel()
            settlePoll = Task { [weak self] in
                var previous: CGSize?
                var waited: Duration = .zero
                while !Task.isCancelled {
                    do { try await Task.sleep(for: Self.settleInterval) } catch { return }
                    guard let self, let view = self.container else { return }
                    // A window in the Dock has no honest bounds to settle on; the
                    // restore observer starts a fresh poll.
                    if view.window?.isMiniaturized == true { return }
                    let size = view.bounds.size
                    waited += Self.settleInterval
                    if size == previous || waited >= Self.settleTimeout {
                        self.settlePoll = nil
                        self.onResync?(size)
                        return
                    }
                    previous = size
                }
            }
        }

        func cancelSettlePoll() {
            settlePoll?.cancel()
            settlePoll = nil
        }
    }
}
