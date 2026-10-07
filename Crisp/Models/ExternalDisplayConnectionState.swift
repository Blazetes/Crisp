struct ExternalDisplayConnectionState {
    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
        let isConnected: Bool
        let isAvailable: Bool
        let isProtected: Bool
    }

    let entries: [Entry]
    var columnCount: Int { min(4, max(1, entries.count)) }
    var rowCount: Int { (entries.count + columnCount - 1) / columnCount }
    var hasProtectedDisplay: Bool { entries.contains { $0.isProtected } }
    var isOn: Bool { entries.contains { $0.isConnected && !$0.isProtected } }
    var canReconnect: Bool { entries.contains { !$0.isConnected && $0.isAvailable } }
    var canDisconnect: Bool { entries.contains { $0.isConnected && !$0.isProtected } }

    static func make(connected: [DisplayConnectionPlan.Display], disconnected: [DisplayConnectionPlan.Display],
                     canRestoreBuiltin: Bool = false) -> Self {
        let held = Set(disconnected.map(\.uuid))
        let physical = connected.filter { !$0.isVirtual && !held.contains($0.uuid) }
        let active = physical.filter(\.isActive)
        let keeper = active.first(where: { $0.isBuiltin }) ?? active.first(where: { $0.isMain }) ?? active.first
        let protectedUUID = keeper?.isBuiltin == false && !canRestoreBuiltin ? keeper?.uuid : nil
        var seen: Set<String> = []
        let external = (physical + disconnected).filter {
            !$0.isBuiltin && !$0.isVirtual && seen.insert($0.uuid).inserted
        }.sorted { $0.uuid < $1.uuid }
        // UUID ordering keeps names in place when WindowServer changes the online list.
        let counts = Dictionary(grouping: external, by: \.name).mapValues(\.count)
        var occurrence: [String: Int] = [:]
        return Self(entries: external.map { display in
            occurrence[display.name, default: 0] += 1
            let suffix = counts[display.name, default: 0] > 1 ? " (\(occurrence[display.name, default: 1]))" : ""
            return Entry(id: display.uuid, name: display.name + suffix, isConnected: !held.contains(display.uuid),
                         isAvailable: display.isAvailable, isProtected: display.uuid == protectedUUID)
        })
    }
}
