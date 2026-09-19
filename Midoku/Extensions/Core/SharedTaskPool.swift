import Foundation

/// Cancels abandoned work without cancelling another caller awaiting the same image.
actor SharedTaskPool<Value: Sendable> {
    private struct Pending {
        let id: UUID
        let task: Task<Value, Error>
        var waiters: Set<UUID>
    }
    private var pending: [String: Pending] = [:]

    func value(for key: String, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let waiter = UUID()
        let task: Task<Value, Error>
        let id: UUID
        if var current = pending[key] {
            current.waiters.insert(waiter); pending[key] = current; task = current.task; id = current.id
        } else {
            id = UUID()
            task = Task { try await operation() }
            pending[key] = Pending(id: id, task: task, waiters: [waiter])
        }
        return try await withTaskCancellationHandler {
            defer { if pending[key]?.id == id { pending[key] = nil } }
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { await self.release(key, waiter: waiter) }
        }
    }

    func cancelAll() {
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll()
    }

    private func release(_ key: String, waiter: UUID) {
        guard var current = pending[key], current.waiters.remove(waiter) != nil else { return }
        if current.waiters.isEmpty { current.task.cancel(); pending[key] = nil }
        else { pending[key] = current }
    }
}
