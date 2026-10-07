import XCTest

final class ExternalDisplayConnectionStateTests: XCTestCase {
    private let builtin = DisplayConnectionPlan.Display(uuid: "builtin", isBuiltin: true, name: "Built-in")

    func testOneToFourNamesStayOnOneRowAndFiveToEightUseTwo() {
        for count in 1...8 {
            let external = (0..<count).map { DisplayConnectionPlan.Display(uuid: "external-\($0)", name: "Monitor \($0)") }
            let state = ExternalDisplayConnectionState.make(connected: external + [builtin], disconnected: [])
            XCTAssertEqual(state.entries.count, count)
            XCTAssertEqual(state.columnCount, min(4, count))
            XCTAssertEqual(state.rowCount, count <= 4 ? 1 : 2)
            XCTAssertTrue(state.isOn)
            XCTAssertFalse(state.hasProtectedDisplay)
        }
    }

    func testEmptyAndOverflowAreNotHardCapped() {
        let empty = ExternalDisplayConnectionState.make(connected: [builtin], disconnected: [])
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertEqual(empty.rowCount, 0)
        let external = (0..<9).map { DisplayConnectionPlan.Display(uuid: "external-\($0)", name: "Monitor \($0)") }
        XCTAssertEqual(ExternalDisplayConnectionState.make(connected: external + [builtin], disconnected: []).rowCount, 3)
    }

    func testMixedStateKeepsNamesAndOrderWhileOfferingBothDirections() {
        let first = DisplayConnectionPlan.Display(uuid: "a", name: "Mi Monitor")
        let second = DisplayConnectionPlan.Display(uuid: "b", name: "DELL U2723QE")
        let all = ExternalDisplayConnectionState.make(connected: [second, builtin, first], disconnected: [])
        let mixed = ExternalDisplayConnectionState.make(connected: [builtin, second], disconnected: [first])
        XCTAssertEqual(all.entries.map(\.id), mixed.entries.map(\.id))
        XCTAssertEqual(all.entries.map(\.name), mixed.entries.map(\.name))
        XCTAssertFalse(mixed.entries[0].isConnected)
        XCTAssertTrue(mixed.entries[1].isConnected)
        XCTAssertTrue(mixed.isOn && mixed.canReconnect && mixed.canDisconnect)
        let off = ExternalDisplayConnectionState.make(connected: [builtin], disconnected: [second, first])
        XCTAssertFalse(off.isOn)
        XCTAssertTrue(off.canReconnect)
        XCTAssertFalse(off.canDisconnect)
    }

    func testBuiltinAndVirtualRecordsAreExcludedAndHeldOverridesStaleOnlineList() {
        let external = DisplayConnectionPlan.Display(uuid: "external", name: "Mi Monitor")
        let virtual = DisplayConnectionPlan.Display(uuid: "virtual", isVirtual: true, name: "Virtual")
        let state = ExternalDisplayConnectionState.make(connected: [builtin, virtual, external],
                                                       disconnected: [builtin, external, external, virtual])
        XCTAssertEqual(state.entries.count, 1)
        XCTAssertFalse(state.entries[0].isConnected)
    }

    func testDesktopMainIsProtectedButDoesNotKeepOtherDisplaySwitchOn() {
        let main = DisplayConnectionPlan.Display(uuid: "a", isMain: true, name: "Main")
        let other = DisplayConnectionPlan.Display(uuid: "b", name: "Other")
        let on = ExternalDisplayConnectionState.make(connected: [main, other], disconnected: [])
        XCTAssertTrue(on.entries[0].isProtected)
        XCTAssertTrue(on.isOn && on.canDisconnect)
        let off = ExternalDisplayConnectionState.make(connected: [main], disconnected: [other])
        XCTAssertTrue(off.hasProtectedDisplay)
        XCTAssertFalse(off.isOn)
        XCTAssertTrue(off.canReconnect)
        let only = ExternalDisplayConnectionState.make(connected: [main], disconnected: [])
        XCTAssertFalse(only.canDisconnect || only.canReconnect)
    }

    func testUnavailableRecordCannotBeRestored() {
        let missing = DisplayConnectionPlan.Display(uuid: "missing", name: "Unplugged", isAvailable: false)
        let state = ExternalDisplayConnectionState.make(connected: [builtin], disconnected: [missing])
        XCTAssertFalse(state.entries[0].isConnected)
        XCTAssertFalse(state.entries[0].isAvailable)
        XCTAssertFalse(state.canReconnect)
    }

    func testRestorableBuiltinAllowsTheOnlyExternalToBeSwitchedOffSafely() {
        let external = DisplayConnectionPlan.Display(uuid: "external", name: "Mi Monitor")
        let state = ExternalDisplayConnectionState.make(connected: [external], disconnected: [builtin], canRestoreBuiltin: true)
        XCTAssertFalse(state.hasProtectedDisplay)
        XCTAssertTrue(state.isOn && state.canDisconnect)
    }

    func testDuplicateNamesAreDistinguishedWithoutDiscardingLongName() {
        let name = "A very long monitor product name with a model and serial number"
        let first = DisplayConnectionPlan.Display(uuid: "a", name: name)
        let second = DisplayConnectionPlan.Display(uuid: "b", name: name)
        let state = ExternalDisplayConnectionState.make(connected: [second, builtin, first], disconnected: [])
        XCTAssertEqual(state.entries.map(\.name), [name + " (1)", name + " (2)"])
    }

    func testInactiveMirrorTargetCannotProtectTheDesktop() {
        let mirror = DisplayConnectionPlan.Display(uuid: "a", isMain: true, isActive: false, name: "Mirror")
        let source = DisplayConnectionPlan.Display(uuid: "b", name: "Source")
        let state = ExternalDisplayConnectionState.make(connected: [mirror, source], disconnected: [])
        XCTAssertFalse(state.entries[0].isProtected)
        XCTAssertTrue(state.entries[1].isProtected)
    }
}
