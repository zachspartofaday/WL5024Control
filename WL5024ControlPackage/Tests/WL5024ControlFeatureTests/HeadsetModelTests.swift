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
