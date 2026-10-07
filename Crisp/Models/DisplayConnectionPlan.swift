struct DisplayConnectionPlan: Equatable {
    enum Action: Equatable {
        case toggleAll
        case reconnectAll
        case disconnectAll
    }

    struct Display {
        let uuid: String
        var isBuiltin = false
        var isMain = false
        var isVirtual = false
        var isActive = true
        var name = ""
        var isAvailable = true
    }

    let reconnectUUIDs: [String]
    let disconnectUUIDs: [String]

    static func make(action: Action, connected: [Display], disconnected: [String], builtinUUIDs: Set<String> = []) -> Self {
        var seen: Set<String> = []
        let held = disconnected.filter { seen.insert($0).inserted }
        if action == .reconnectAll || (action == .toggleAll && !held.isEmpty) {
            let builtins = builtinUUIDs.union(connected.filter(\.isBuiltin).map(\.uuid))
            return Self(reconnectUUIDs: held.filter { !builtins.contains($0) }, disconnectUUIDs: [])
        }
        seen = Set(held)
        let physical = connected.filter { !$0.isVirtual && seen.insert($0.uuid).inserted }
        let active = physical.filter(\.isActive)
        guard let keeper = active.first(where: { $0.isBuiltin }) ?? active.first(where: { $0.isMain }) ?? active.first else {
            return Self(reconnectUUIDs: [], disconnectUUIDs: [])
        }
        return Self(reconnectUUIDs: [], disconnectUUIDs: physical.filter { !$0.isBuiltin && $0.uuid != keeper.uuid }.map(\.uuid))
    }
}
