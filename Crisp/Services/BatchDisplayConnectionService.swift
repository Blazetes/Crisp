import Foundation
import CoreGraphics
import Combine

@MainActor
final class BatchDisplayConnectionService: ObservableObject {
    static let shared = BatchDisplayConnectionService()
    private init() {}

    @Published private(set) var isBusy = false
    @Published private(set) var failures: [Failure] = []

    struct Failure: Identifiable {
        let id: String
        let name: String
        let error: PhysicalDisplayToggleService.ToggleError
        var expectedConnected: Bool? = nil
    }

    func connectedDisplays(using manager: DisplayManager) -> [DisplayConnectionPlan.Display] {
        manager.displays.map {
            .init(uuid: $0.displayUUID, isBuiltin: $0.isBuiltin, isMain: $0.isMain,
                  isVirtual: VirtualDisplayService.shared.isVirtualDisplay($0.displayID),
                  isActive: CGDisplayIsActive($0.displayID) != 0, name: $0.name)
        }
    }

    func state(using manager: DisplayManager) -> ExternalDisplayConnectionState {
        let service = PhysicalDisplayToggleService.shared
        let held: [DisplayConnectionPlan.Display] = service.disconnected.map {
            .init(uuid: $0.uuid, isBuiltin: service.isBuiltinDisconnectedDisplay($0),
                  name: $0.name, isAvailable: service.isAvailableForReconnect($0))
        }
        return .make(connected: connectedDisplays(using: manager), disconnected: held,
                     canRestoreBuiltin: held.contains { $0.isBuiltin && $0.isAvailable })
    }

    func perform(_ action: DisplayConnectionPlan.Action, using manager: DisplayManager) async -> [Failure] {
        guard !isBusy else { return failures }
        isBusy = true
        failures = []
        defer { isBusy = false; manager.refreshDisplays() }

        manager.refreshDisplays()
        let shouldConnect = action == .reconnectAll || (action == .toggleAll && !state(using: manager).isOn)
        if !shouldConnect, !(await restoreBuiltinIfNeeded(using: manager)) { return failures }
        let service = PhysicalDisplayToggleService.shared
        let records = service.disconnected.filter {
            !service.isBuiltinDisconnectedDisplay($0) && service.isAvailableForReconnect($0)
        }
        let plan = DisplayConnectionPlan.make(
            action: shouldConnect ? .reconnectAll : .disconnectAll,
            connected: connectedDisplays(using: manager),
            disconnected: service.disconnected.map(\.uuid),
            builtinUUIDs: Set(service.disconnected.filter { service.isBuiltinDisconnectedDisplay($0) }.map(\.uuid))
        )
        let available = Set(records.map(\.uuid))
        for uuid in shouldConnect ? plan.reconnectUUIDs.filter({ available.contains($0) }) : plan.disconnectUUIDs {
            let name = manager.displays.first { $0.displayUUID == uuid }?.name ?? records.first { $0.uuid == uuid }?.name ?? uuid
            if !(await change(uuid: uuid, connect: shouldConnect, name: name, using: manager)) { break }
        }
        return failures
    }

    func toggle(uuid: String, using manager: DisplayManager) async {
        guard !isBusy, let entry = state(using: manager).entries.first(where: { $0.id == uuid }),
              !entry.isProtected, entry.isConnected || entry.isAvailable else { return }
        isBusy = true
        failures = []
        defer { isBusy = false; manager.refreshDisplays() }
        if entry.isConnected, !(await restoreBuiltinIfNeeded(using: manager)) { return }
        _ = await change(uuid: uuid, connect: !entry.isConnected, name: entry.name, using: manager)
    }

    func clearSettledTimeouts(using manager: DisplayManager) {
        guard !PhysicalDisplayToggleService.shared.configurationInProgress else { return }
        let online = Set(manager.displays.map(\.displayUUID))
        failures.removeAll { failure in
            guard case .timedOut = failure.error, let expected = failure.expectedConnected else { return false }
            return online.contains(failure.id) == expected
        }
    }

    private func restoreBuiltinIfNeeded(using manager: DisplayManager) async -> Bool {
        let service = PhysicalDisplayToggleService.shared
        service.holdBuiltinForExternalDisconnect()
        guard let builtin = service.disconnected.first(where: { service.isBuiltinDisconnectedDisplay($0) }),
              service.isAvailableForReconnect(builtin) else { return true }
        return await change(uuid: builtin.uuid, connect: true, name: builtin.name, using: manager)
    }

    // API success alone is not proof of a connection change; wait for online enumeration.
    private func change(uuid: String, connect: Bool, name: String, using manager: DisplayManager) async -> Bool {
        let service = PhysicalDisplayToggleService.shared
        let result: Result<Void, PhysicalDisplayToggleService.ToggleError>
        if connect {
            result = await InputSwitchService.shared.reconnect(uuid: uuid)
        } else {
            manager.refreshDisplays()
            guard let display = manager.displays.first(where: { $0.displayUUID == uuid }), !display.isBuiltin,
                  !VirtualDisplayService.shared.isVirtualDisplay(display.displayID) else { return true }
            result = await service.disconnect(display)
        }
        if case .failure(let error) = result {
            failures.append(Failure(id: uuid, name: name, error: error, expectedConnected: connect))
            if case .timedOut = error { return false }
            if case .configurationInProgress = error { return false }
            return true
        }
        for _ in 0..<20 {
            manager.refreshDisplays()
            if manager.displays.contains(where: { $0.displayUUID == uuid }) == connect { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        failures.append(Failure(id: uuid, name: name, error: .timedOut, expectedConnected: connect))
        return false
    }
}
