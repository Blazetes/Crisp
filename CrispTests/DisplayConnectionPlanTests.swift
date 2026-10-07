import XCTest

final class DisplayConnectionPlanTests: XCTestCase {
    private let displays: [DisplayConnectionPlan.Display] = [
        .init(uuid: "external-main", isMain: true),
        .init(uuid: "builtin", isBuiltin: true),
        .init(uuid: "external-secondary")
    ]

    func testDisconnectAllKeepsBuiltinEvenWhenAnExternalIsMain() {
        let plan = DisplayConnectionPlan.make(action: .disconnectAll, connected: displays, disconnected: [])
        XCTAssertEqual(plan.disconnectUUIDs, ["external-main", "external-secondary"])
        XCTAssertTrue(plan.reconnectUUIDs.isEmpty)
    }

    func testDesktopKeepsMainOrFirstPhysicalDisplay() {
        let desktop = displays.filter { !$0.isBuiltin }
        XCTAssertEqual(DisplayConnectionPlan.make(action: .disconnectAll, connected: desktop, disconnected: []).disconnectUUIDs,
                       ["external-secondary"])
        let unnamedMain: [DisplayConnectionPlan.Display] = [.init(uuid: "first"), .init(uuid: "second")]
        XCTAssertEqual(DisplayConnectionPlan.make(action: .disconnectAll, connected: unnamedMain, disconnected: []).disconnectUUIDs,
                       ["second"])
    }

    func testVirtualInactiveAndHeldDisplaysCannotServeAsKeeper() {
        let topology: [DisplayConnectionPlan.Display] = [
            .init(uuid: "virtual-main", isMain: true, isVirtual: true),
            .init(uuid: "sleeping-builtin", isBuiltin: true, isActive: false),
            .init(uuid: "held-builtin", isBuiltin: true),
            .init(uuid: "physical")
        ]
        let plan = DisplayConnectionPlan.make(action: .disconnectAll, connected: topology, disconnected: ["held-builtin"])
        XCTAssertTrue(plan.disconnectUUIDs.isEmpty)
    }

    func testMixedStateToggleReconnectsAllAndDeduplicatesRecords() {
        let plan = DisplayConnectionPlan.make(action: .toggleAll, connected: displays, disconnected: ["held", "held", "other"])
        XCTAssertEqual(plan.reconnectUUIDs, ["held", "other"])
        XCTAssertTrue(plan.disconnectUUIDs.isEmpty)
    }

    func testConnectedToggleDisconnectsOthersAndReconnectIsIdempotent() {
        XCTAssertEqual(DisplayConnectionPlan.make(action: .toggleAll, connected: displays, disconnected: []),
                       DisplayConnectionPlan.make(action: .disconnectAll, connected: displays, disconnected: []))
        XCTAssertTrue(DisplayConnectionPlan.make(action: .reconnectAll, connected: displays, disconnected: []).disconnectUUIDs.isEmpty)
        XCTAssertTrue(DisplayConnectionPlan.make(action: .reconnectAll, connected: displays, disconnected: []).reconnectUUIDs.isEmpty)
    }

    func testEmptySingleAndDuplicateTopologiesDoNotDisconnectLastScreen() {
        let topologies: [[DisplayConnectionPlan.Display]] = [[], [.init(uuid: "only")], [.init(uuid: "only"), .init(uuid: "only")]]
        for topology in topologies {
            XCTAssertTrue(DisplayConnectionPlan.make(action: .disconnectAll, connected: topology, disconnected: []).disconnectUUIDs.isEmpty)
        }
    }
}
