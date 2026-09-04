import Foundation
import Testing
@testable import WL5024ControlFeature

@MainActor
struct HeadsetModelTests {
    @Test func startupAppliesInitialRevisionBeforeReturning() async {
        let controller = RecordingHeadsetController()
        let model = HeadsetModel(demoMode: true, controller: controller)

        await model.start()

        #expect(model.didStart)
        #expect(model.snapshot.connection == .connected(.receiver))
        #expect(model.value(for: .bass) == .integer(0))
    }

    @Test func olderAndDuplicateRevisionsCannotOverwriteNewerState() {
        let model = HeadsetModel(demoMode: true, controller: RecordingHeadsetController())
        var older = HeadsetSnapshot.demo()
        older.values[.bass] = .integer(1)
        var newer = HeadsetSnapshot.demo()
        newer.values[.bass] = .integer(3)

        model.apply(.init(revision: 2, snapshot: newer))
        model.apply(.init(revision: 1, snapshot: older))
        model.apply(.init(revision: 2, snapshot: older))

        #expect(model.value(for: .bass) == .integer(3))
    }

    @Test func formerCommandResultRaceRemainsStableFor25Runs() async {
        for _ in 0..<25 {
            let controller = RecordingHeadsetController()
            let model = HeadsetModel(demoMode: true, controller: controller)
            await model.start()
            let staleStartUpdate = controller.lastUpdate

            await model.set(.bass, to: .integer(3)).value
            if let staleStartUpdate {
                model.apply(staleStartUpdate)
            }

            #expect(model.value(for: .bass) == .integer(3))
        }
    }

    @Test func reconnectAppliesStopAndRestartInRevisionOrder() async {
        let controller = RecordingHeadsetController()
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        await model.reconnect().value

        #expect(controller.stopCount == 1)
        #expect(controller.startCount == 2)
        #expect(model.snapshot.connection == .connected(.receiver))
        #expect(controller.lastUpdate?.revision == 3)
    }

    @Test func coalescesRapidWritesAndCommitsLatestValue() async {
        let controller = RecordingHeadsetController()
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        model.set(.bass, to: .integer(1))
        model.set(.bass, to: .integer(2))
        let completion = model.set(.bass, to: .integer(3))
        await completion.value

        #expect(controller.writes == [.init(key: .bass, value: .integer(3))])
        #expect(model.value(for: .bass) == .integer(3))
        #expect(!model.isCommandInFlight)
    }

    @Test func serializesCommandsAcrossDifferentSettings() async {
        let controller = RecordingHeadsetController()
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        model.set(.bass, to: .integer(1))
        let completion = model.set(.treble, to: .integer(2))
        await completion.value

        #expect(controller.writes.map(\.key) == [.bass, .treble])
    }

    @Test func validationPendingControlDoesNotReachController() async {
        let controller = RecordingHeadsetController()
        let model = HeadsetModel(demoMode: false, controller: controller)

        await model.set(.automaticMedia, to: .boolean(false)).value

        #expect(controller.writes.isEmpty)
        #expect(model.failure?.primaryAction == .dismiss)
    }

    @Test func readOnlyDiscoveryPublishesProgressAndSummary() async {
        let controller = RecordingHeadsetController()
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        await model.runReadOnlyDiscovery().value

        #expect(controller.discoveryCount == 1)
        #expect(model.discoveryState == .completed)
        #expect(model.discoveryProgress == nil)
        #expect(model.lastDiscoverySummary?.queryCount == 1)
    }

    @Test func settingsActionsAreRejectedWhileDiscoveryRuns() async {
        let controller = BlockingDiscoveryController()
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        let discovery = model.runReadOnlyDiscovery()
        // Wait until discovery is actively running.
        for _ in 0..<50 where model.discoveryState != .running {
            await Task.yield()
        }
        #expect(model.discoveryState == .running)

        await model.set(.bass, to: .integer(3)).value
        await model.refresh().value
        await model.reconnect().value

        #expect(controller.writes.isEmpty)
        #expect(controller.refreshCount == 0)
        #expect(model.failure?.primaryAction == .dismiss)
        model.retryLastAction()
        #expect(controller.writes.isEmpty)
        #expect(controller.refreshCount == 0)
        controller.finishDiscovery()
        await discovery.value
        #expect(model.discoveryState == .completed)
    }

    @Test func cancellingQueuedDiscoveryPreservesNoSilentWrites() async {
        let controller = BlockingDiscoveryController()
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        let discovery = model.runReadOnlyDiscovery()
        for _ in 0..<50 where model.discoveryState != .running {
            await Task.yield()
        }
        // Settings path is exclusive: nothing enqueues behind discovery.
        await model.set(.bass, to: .integer(3)).value
        #expect(controller.writes.isEmpty)
        model.cancelReadOnlyDiscovery()
        controller.finishDiscovery(cancelled: true)
        await discovery.value
        #expect(model.discoveryState == .cancelled)
        #expect(controller.writes.isEmpty)
    }

    @Test func failureHaltsQueueUntilRetrySucceeds() async {
        let controller = FailOnceController(failKey: .bass)
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        model.set(.bass, to: .integer(1))
        let treble = model.set(.treble, to: .integer(2))
        await treble.value

        // Second command halted behind the failure; no dead retry yet.
        #expect(controller.writes.map(\.key) == [.bass])
        #expect(model.failure != nil)
        model.retryLastAction()
        // Wait for retry + halted treble to drain.
        for _ in 0..<100 where controller.writes.map(\.key) != [.bass, .bass, .treble] {
            await Task.yield()
        }
        #expect(controller.writes.map(\.key) == [.bass, .bass, .treble])
        #expect(model.failure == nil)
    }

    @Test func reconnectRunsBeforeCommandsPreservedBehindFailure() async {
        let controller = FailOnceController(
            failKey: .bass,
            failure: .transport("fixture link failure")
        )
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        model.set(.bass, to: .integer(1))
        let treble = model.set(.treble, to: .integer(2))
        await treble.value

        #expect(controller.operations == [.start, .set(.bass)])
        let originalFailure = model.failure
        await model.set(.mid, to: .integer(3)).value
        await model.refresh().value
        await model.runReadOnlyDiscovery().value
        #expect(controller.operations == [.start, .set(.bass)])
        #expect(model.failure == originalFailure)
        #expect(model.discoveryState == .idle)

        await model.reconnect().value

        #expect(controller.operations == [
            .start,
            .set(.bass),
            .stop,
            .start,
            .set(.treble),
        ])
        #expect(model.value(for: .treble) == .integer(2))
        #expect(model.failure == nil)
    }

    @Test func dismissAbandonsRetryAndResumesQueue() async {
        let controller = FailOnceController(failKey: .bass)
        let model = HeadsetModel(demoMode: true, controller: controller)
        await model.start()

        model.set(.bass, to: .integer(1))
        let treble = model.set(.treble, to: .integer(2))
        await treble.value

        #expect(model.failure != nil)
        model.dismissFailure()
        for _ in 0..<100 where controller.writes.map(\.key) != [.bass, .treble] {
            await Task.yield()
        }
        #expect(controller.writes.map(\.key) == [.bass, .treble])
        #expect(model.failure == nil)
        // No retained retry after dismiss: retry is a no-op.
        model.retryLastAction()
        #expect(controller.writes.map(\.key) == [.bass, .treble])
    }
}

@MainActor
private final class BlockingDiscoveryController: HeadsetController {
    struct Write: Equatable {
        let key: HeadsetSettingKey
        let value: SettingValue
    }

    private var snapshot = HeadsetSnapshot.demo()
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation
    private var revision: UInt64 = 0
    private(set) var writes: [Write] = []
    private(set) var refreshCount = 0
    private var resumeDiscovery: CheckedContinuation<Void, Error>?

    init() {
        let pair = AsyncStream.makeStream(of: HeadsetEvent.self, bufferingPolicy: .bufferingNewest(10))
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() async -> AsyncStream<HeadsetEvent> { stream }

    func start() async -> HeadsetStateUpdate { publish() }

    func stop() async -> HeadsetStateUpdate { publish() }

    func refresh() async throws -> HeadsetStateUpdate {
        refreshCount += 1
        return publish()
    }

    func set(_ key: HeadsetSettingKey, value: SettingValue) async throws -> HeadsetStateUpdate {
        writes.append(Write(key: key, value: value))
        snapshot.values[key] = value
        return publish()
    }

    func perform(_ key: HeadsetSettingKey) async throws -> HeadsetStateUpdate { publish() }

    func discoverReadOnly(
        progress: @escaping @MainActor @Sendable (ReadOnlyDiscoveryProgress) -> Void
    ) async throws -> ReadOnlyDiscoveryResult {
        progress(.init(completed: 0, total: 2, currentProbe: "blocked"))
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            resumeDiscovery = c
        }
        progress(.init(completed: 2, total: 2, currentProbe: "blocked"))
        return ReadOnlyDiscoveryResult(
            update: publish(),
            summary: .init(
                queryCount: 2,
                responseCount: 2,
                timeoutCount: 0,
                failureCount: 0,
                decodedSettingCount: 1,
                elapsedSeconds: 0
            )
        )
    }

    func finishDiscovery(cancelled: Bool = false) {
        if cancelled {
            resumeDiscovery?.resume(throwing: CancellationError())
        } else {
            resumeDiscovery?.resume()
        }
        resumeDiscovery = nil
    }

    private func publish() -> HeadsetStateUpdate {
        revision += 1
        let update = HeadsetStateUpdate(revision: revision, snapshot: snapshot)
        continuation.yield(.snapshot(update))
        return update
    }
}

@MainActor
private final class FailOnceController: HeadsetController {
    enum Operation: Equatable {
        case start
        case stop
        case set(HeadsetSettingKey)
    }

    struct Write: Equatable {
        let key: HeadsetSettingKey
        let value: SettingValue
    }

    private var snapshot = HeadsetSnapshot.demo()
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation
    private var revision: UInt64 = 0
    private(set) var writes: [Write] = []
    private(set) var operations: [Operation] = []
    private let failKey: HeadsetSettingKey
    private let failure: HeadsetError
    private var didFail = false

    init(failKey: HeadsetSettingKey, failure: HeadsetError = .timeout) {
        self.failKey = failKey
        self.failure = failure
        let pair = AsyncStream.makeStream(of: HeadsetEvent.self, bufferingPolicy: .bufferingNewest(10))
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() async -> AsyncStream<HeadsetEvent> { stream }
    func start() async -> HeadsetStateUpdate {
        operations.append(.start)
        return publish()
    }
    func stop() async -> HeadsetStateUpdate {
        operations.append(.stop)
        return publish()
    }
    func refresh() async throws -> HeadsetStateUpdate { publish() }
    func set(_ key: HeadsetSettingKey, value: SettingValue) async throws -> HeadsetStateUpdate {
        await Task.yield()
        writes.append(Write(key: key, value: value))
        operations.append(.set(key))
        if key == failKey, !didFail {
            didFail = true
            throw failure
        }
        snapshot.values[key] = value
        return publish()
    }
    func perform(_ key: HeadsetSettingKey) async throws -> HeadsetStateUpdate { publish() }
    func discoverReadOnly(
        progress: @escaping @MainActor @Sendable (ReadOnlyDiscoveryProgress) -> Void
    ) async throws -> ReadOnlyDiscoveryResult {
        progress(.init(completed: 1, total: 1, currentProbe: "test"))
        return ReadOnlyDiscoveryResult(update: publish(), summary: .init(queryCount: 1, responseCount: 1, timeoutCount: 0, failureCount: 0, decodedSettingCount: 1, elapsedSeconds: 0))
    }

    private func publish() -> HeadsetStateUpdate {
        revision += 1
        let update = HeadsetStateUpdate(revision: revision, snapshot: snapshot)
        continuation.yield(.snapshot(update))
        return update
    }
}

@MainActor
private final class RecordingHeadsetController: HeadsetController {
    struct Write: Equatable {
        let key: HeadsetSettingKey
        let value: SettingValue
    }

    private var snapshot = HeadsetSnapshot.demo()
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation
    private var revision: UInt64 = 0
    private(set) var writes: [Write] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var discoveryCount = 0
    private(set) var lastUpdate: HeadsetStateUpdate?

    init() {
        let pair = AsyncStream.makeStream(of: HeadsetEvent.self, bufferingPolicy: .bufferingNewest(10))
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() async -> AsyncStream<HeadsetEvent> { stream }

    func start() async -> HeadsetStateUpdate {
        startCount += 1
        snapshot.connection = .connected(.receiver)
        return publish()
    }

    func stop() async -> HeadsetStateUpdate {
        stopCount += 1
        snapshot.connection = .idle
        return publish()
    }

    func refresh() async throws -> HeadsetStateUpdate {
        await Task.yield()
        return publish()
    }

    func set(_ key: HeadsetSettingKey, value: SettingValue) async throws -> HeadsetStateUpdate {
        await Task.yield()
        writes.append(Write(key: key, value: value))
        snapshot.values[key] = value
        return publish()
    }

    func perform(_ key: HeadsetSettingKey) async throws -> HeadsetStateUpdate {
        await Task.yield()
        return publish()
    }

    func discoverReadOnly(
        progress: @escaping @MainActor @Sendable (ReadOnlyDiscoveryProgress) -> Void
    ) async throws -> ReadOnlyDiscoveryResult {
        discoveryCount += 1
        progress(.init(completed: 1, total: 1, currentProbe: "test.getter"))
        return ReadOnlyDiscoveryResult(
            update: publish(),
            summary: .init(
                queryCount: 1,
                responseCount: 1,
                timeoutCount: 0,
                failureCount: 0,
                decodedSettingCount: 1,
                elapsedSeconds: 0
            )
        )
    }

    private func publish() -> HeadsetStateUpdate {
        revision += 1
        let update = HeadsetStateUpdate(revision: revision, snapshot: snapshot)
        lastUpdate = update
        continuation.yield(.snapshot(update))
        return update
    }
}
