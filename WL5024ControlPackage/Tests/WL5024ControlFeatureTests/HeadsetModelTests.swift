import Foundation
import Testing
@testable import WL5024ControlFeature

@MainActor
struct HeadsetModelTests {
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
    private(set) var writes: [Write] = []

    init() {
        let pair = AsyncStream.makeStream(of: HeadsetEvent.self, bufferingPolicy: .bufferingNewest(10))
        stream = pair.stream
        continuation = pair.continuation
    }

    func events() async -> AsyncStream<HeadsetEvent> { stream }

    func start() async {
        continuation.yield(.snapshot(snapshot))
    }

    func stop() async {}

    func refresh() async throws -> HeadsetSnapshot {
        await Task.yield()
        return snapshot
    }

    func set(_ key: HeadsetSettingKey, value: SettingValue) async throws -> HeadsetSnapshot {
        await Task.yield()
        writes.append(Write(key: key, value: value))
        snapshot.values[key] = value
        return snapshot
    }

    func perform(_ key: HeadsetSettingKey) async throws -> HeadsetSnapshot {
        await Task.yield()
        return snapshot
    }
}
