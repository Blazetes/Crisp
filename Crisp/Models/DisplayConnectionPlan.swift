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
    }

    let reconnectUUIDs: [String]
    let disconnectUUIDs: [String]

    static func make(action: Action, connected: [Display], disconnected: [String]) -> Self {
        var seen: Set<String> = []
        let held = disconnected.filter { seen.insert($0).inserted }
        if action == .reconnectAll || (action == .toggleAll && !held.isEmpty) {
            return Self(reconnectUUIDs: held, disconnectUUIDs: [])
        }
        seen = Set(held)
        let active = connected.filter { !$0.isVirtual && $0.isActive && seen.insert($0.uuid).inserted }
        let keeper = active.first(where: { $0.isBuiltin }) ?? active.first(where: { $0.isMain }) ?? active.first
        return Self(reconnectUUIDs: [], disconnectUUIDs: active.filter { $0.uuid != keeper?.uuid }.map(\.uuid))
    }
}
