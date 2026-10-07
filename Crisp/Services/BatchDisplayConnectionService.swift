import Foundation
import CoreGraphics
import Combine

@MainActor
final class BatchDisplayConnectionService: ObservableObject {
    static let shared = BatchDisplayConnectionService()
    private init() {}

    @Published private(set) var isBusy = false

    struct Failure: Identifiable {
        let id: String
        let name: String
        let error: PhysicalDisplayToggleService.ToggleError
    }

    func perform(_ action: DisplayConnectionPlan.Action, using manager: DisplayManager) async -> [Failure] {
        guard !isBusy else { return [] }
        isBusy = true
        defer { isBusy = false; manager.refreshDisplays() }

        let service = PhysicalDisplayToggleService.shared
        let records = service.disconnected
        let plan = DisplayConnectionPlan.make(
            action: action,
            connected: manager.displays.map {
                .init(uuid: $0.displayUUID, isBuiltin: $0.isBuiltin, isMain: $0.isMain,
                      isVirtual: VirtualDisplayService.shared.isVirtualDisplay($0.displayID),
                      isActive: CGDisplayIsActive($0.displayID) != 0)
            },
            disconnected: records.map(\.uuid)
        )
        var failures: [Failure] = []
        for uuid in plan.reconnectUUIDs {
            let result = await InputSwitchService.shared.reconnect(uuid: uuid)
            manager.refreshDisplays()
            if case .failure(let error) = result {
                failures.append(Failure(id: uuid, name: records.first { $0.uuid == uuid }?.name ?? uuid, error: error))
                if case .timedOut = error { return failures }
            }
        }
        for uuid in plan.disconnectUUIDs {
            manager.refreshDisplays()
            guard let display = manager.displays.first(where: { $0.displayUUID == uuid }),
                  !service.isDisconnected(uuid: uuid) else { continue }
            let result = await service.disconnect(display)
            if case .failure(let error) = result {
                failures.append(Failure(id: uuid, name: display.name, error: error))
                if case .timedOut = error { return failures }
            }
        }
        return failures
    }
}
