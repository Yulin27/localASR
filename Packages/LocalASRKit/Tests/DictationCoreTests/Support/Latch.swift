import Foundation

/// A test-controlled suspension point.
///
/// Lets a test park a port call, act on the coordinator, and only then let the call finish.
/// That is what makes cancellation and staleness deterministic without a single sleep.
///
/// The ordering inside ``arriveAndWait()`` is load-bearing and must not be relaxed:
///
/// - The cancellation handler wraps the continuation, not the other way round. The
///   continuation body is not cancellable, so a handler placed inside it would never run and
///   the fake would hang forever on cancel.
/// - The open flag is re-checked inside the continuation body, because the handler can fire
///   before the body starts on an already-cancelled task.
/// - The waiter list is drained before anything is resumed, so no continuation is resumed
///   twice.
actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0

    /// Suspends until ``open()`` is called. Returns immediately when already open.
    func arriveAndWait() async {
        arrivals += 1
        if isOpen { return }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isOpen {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        } onCancel: {
            // `@Sendable` and non-async, so it has to hop back into the actor.
            Task { await self.open() }
        }
    }

    /// Releases every waiter. Idempotent.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    /// Closes the latch again, so the next arrival parks.
    func close() {
        isOpen = false
    }
}
