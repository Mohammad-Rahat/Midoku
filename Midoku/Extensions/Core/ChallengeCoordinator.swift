import Foundation
import Observation

@MainActor
@Observable
final class ChallengeCoordinator: ChallengeResolving {
    private(set) var current: SourceChallenge?
    private var pending: [SourceChallenge] = []
    private var isDismissing = false
    @ObservationIgnored private var continuations: [UUID: CheckedContinuation<Void, any Error>] = [:]

    @MainActor
    func resolve(_ challenge: SourceChallenge) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[challenge.id] = continuation
                pending.append(challenge)
                presentNext()
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(id: challenge.id, result: .failure(CancellationError()))
            }
        }
    }

    func retry(id: UUID) {
        // A user action requests one native retry; it does not assert clearance success.
        finish(id: id, result: .success(()))
    }

    func cancel(id: UUID) {
        finish(id: id, result: .failure(CancellationError()))
    }

    func presentationDidDismiss() {
        isDismissing = false
        presentNext()
    }

    private func finish(id: UUID, result: Result<Void, any Error>) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        pending.removeAll { $0.id == id }
        if current?.id == id {
            current = nil
            // Wait for SwiftUI to finish dismissing before exposing another source.
            isDismissing = true
        }
        continuation.resume(with: result)
        presentNext()
    }

    private func presentNext() {
        guard current == nil, !isDismissing, !pending.isEmpty else { return }
        current = pending.removeFirst()
    }
}
