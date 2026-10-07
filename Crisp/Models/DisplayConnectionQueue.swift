@MainActor
final class DisplayConnectionQueue {
    private var tail: Task<Void, Never>?
    private var generation: UInt64 = 0

    func run<Output: Sendable>(_ operation: @escaping @MainActor () async -> Output) async -> Output {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        generation &+= 1
        let requestGeneration = generation
        tail = Task { @MainActor in _ = await task.value }
        let result = await task.value
        if generation == requestGeneration { tail = nil }
        return result
    }
}
