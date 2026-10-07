import XCTest

final class DisplayConnectionQueueTests: XCTestCase {
    @MainActor
    func testOverlappingDisconnectsRecheckTheLastScreenAfterPreviousChange() async {
        let queue = DisplayConnectionQueue()
        var activeScreens = 2
        var inFlight = 0
        var peakInFlight = 0
        let disconnect: @MainActor () async -> Bool = {
            guard activeScreens > 1 else { return false }
            inFlight += 1
            peakInFlight = max(peakInFlight, inFlight)
            try? await Task.sleep(nanoseconds: 10_000_000)
            activeScreens -= 1
            inFlight -= 1
            return true
        }
        async let first = queue.run(disconnect)
        async let second = queue.run(disconnect)
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(activeScreens, 1)
        XCTAssertEqual(peakInFlight, 1)
    }

    @MainActor
    func testQueueContinuesAfterARefusedOperation() async {
        let queue = DisplayConnectionQueue()
        let refused = await queue.run { false }
        let reconnected = await queue.run { true }
        XCTAssertFalse(refused)
        XCTAssertTrue(reconnected)
    }
}
