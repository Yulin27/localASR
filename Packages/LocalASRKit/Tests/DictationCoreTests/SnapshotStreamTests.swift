import Testing

@testable import DictationCore

@Suite("Snapshot observation")
struct SnapshotStreamTests {
    @Test("A subscriber receives the current state immediately")
    func subscriberReceivesCurrentStateImmediately() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        try await harness.startRecording()

        var iterator = await harness.coordinator.snapshots().makeAsyncIterator()
        let first = await iterator.next()

        // No stale first frame: a view that subscribes late renders the truth at once.
        #expect(first?.phase == .recording)
        #expect(first?.sessionID != nil)
    }

    @Test("Every subscriber observes the same transitions")
    func allSubscribersObserveTheSameTransitions() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        let streamA = await harness.coordinator.snapshots()
        let streamB = await harness.coordinator.snapshots()
        let collectorA = Task { await collect(streamA) }
        let collectorB = Task { await collect(streamB) }

        _ = try await harness.runSession()
        await harness.coordinator.shutdown()

        let phasesA = await collectorA.value
        let phasesB = await collectorB.value

        #expect(phasesA == phasesB)
        #expect(phasesA.last == .completed)
        #expect(phasesA.count > 1)
    }

    @Test("Shutting down ends every stream")
    func shutdownEndsEveryStream() async throws {
        let harness = DictationHarness()
        let stream = await harness.coordinator.snapshots()

        await harness.coordinator.shutdown()

        var phases: [DictationPhase] = []
        var iterator = stream.makeAsyncIterator()
        while let snapshot = await iterator.next() {
            phases.append(snapshot.phase)
        }

        #expect(phases == [.idle])
        let remaining = await harness.coordinator.subscriberCount
        #expect(remaining == 0)
    }

    @Test("Subscribing after shutdown yields only the idle state and then ends")
    func subscribingAfterShutdownEndsImmediately() async throws {
        let harness = DictationHarness()
        await harness.coordinator.shutdown()

        var phases: [DictationPhase] = []
        var iterator = await harness.coordinator.snapshots().makeAsyncIterator()
        while let snapshot = await iterator.next() {
            phases.append(snapshot.phase)
        }

        #expect(phases == [.idle])
    }

    @Test("An observer that goes away is removed")
    func terminatedObserverIsRemoved() async throws {
        let harness = DictationHarness()
        let stream = await harness.coordinator.snapshots()
        let registered = await harness.coordinator.subscriberCount
        #expect(registered == 1)

        let consumer = Task {
            for await _ in stream {}
        }
        consumer.cancel()
        _ = await consumer.value

        try await harness.waitUntil("the observer was removed") {
            await harness.coordinator.subscriberCount == 0
        }
    }

    private func collect(_ stream: AsyncStream<SessionSnapshot>) async -> [DictationPhase] {
        var phases: [DictationPhase] = []
        for await snapshot in stream {
            phases.append(snapshot.phase)
        }
        return phases
    }
}
