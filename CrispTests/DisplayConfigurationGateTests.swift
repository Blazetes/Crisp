import XCTest
import Foundation

private final class SimulatedConfiguration: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 2
    private var peak = 0
    private var activeTransactions = 0
    private var completedLate = false
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    var activeScreens: Int { lock.withLock { count } }
    var peakTransactions: Int { lock.withLock { peak } }
    var wasLate: Bool { lock.withLock { completedLate } }

    func commit() -> Bool {
        lock.withLock { activeTransactions += 1; peak = max(peak, activeTransactions) }
        started.signal()
        _ = release.wait(timeout: .now() + 2)
        lock.withLock { count -= 1; activeTransactions -= 1 }
        return true
    }

    func record(late: Bool) { lock.withLock { completedLate = late } }
}

final class DisplayConfigurationGateTests: XCTestCase {
    func testOnlyOneLeaseCanBeActive() {
        let gate = DisplayConfigurationGate()
        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.isPending)
        XCTAssertFalse(gate.begin())
        gate.finish()
        XCTAssertFalse(gate.isPending)
        XCTAssertTrue(gate.begin())
        gate.finish()
    }

    @MainActor
    func testTimeoutCannotReleaseTheGuardForAnotherDisconnect() async {
        let queue = DisplayConnectionQueue()
        let gate = DisplayConfigurationGate()
        let state = SimulatedConfiguration()
        let disconnect: @MainActor @Sendable () async -> Bool = {
            guard state.activeScreens > 1, gate.begin() else { return false }
            return await CGHelpers.runWithTimeout(seconds: 0.02, fallback: false, onOperationFinished: { _, late in
                Task { @MainActor in state.record(late: late); gate.finish() }
            }) { state.commit() }
        }
        let first = await queue.run(disconnect)
        XCTAssertFalse(first)
        XCTAssertTrue(state.started.wait(timeout: .now() + 1) == .success)
        XCTAssertTrue(gate.isPending)
        let second = await queue.run(disconnect)
        XCTAssertFalse(second)
        XCTAssertEqual(state.peakTransactions, 1)
        state.release.signal()
        for _ in 0..<100 where gate.isPending { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(gate.isPending)
        XCTAssertTrue(state.wasLate)
        XCTAssertEqual(state.activeScreens, 1)
        XCTAssertTrue(gate.begin(), "Real completion must unblock later requests")
        gate.finish()
    }

    @MainActor
    func testSuccessfulOperationCompletesBeforeItsReturn() async {
        let gate = DisplayConfigurationGate()
        XCTAssertTrue(gate.begin())
        let result = await CGHelpers.runWithTimeout(seconds: 1, fallback: false,
            onOperationFinished: { _, late in XCTAssertFalse(late); gate.finish() }) { true }
        XCTAssertTrue(result)
        XCTAssertFalse(gate.isPending)
    }

    @MainActor
    func testQueuedOperationPinsIdentityAtSubmission() async {
        let queue = DisplayConnectionQueue()
        var liveIdentity = "requested-display"
        let blocker = Task { @MainActor in
            await queue.run { try? await Task.sleep(nanoseconds: 20_000_000) }
        }
        await Task.yield()
        let requestedIdentity = liveIdentity
        let request = Task { @MainActor in await queue.run { requestedIdentity } }
        liveIdentity = "reassigned-display"
        await blocker.value
        let identity = await request.value
        XCTAssertEqual(identity, "requested-display")
        XCTAssertEqual(liveIdentity, "reassigned-display")
    }
}
