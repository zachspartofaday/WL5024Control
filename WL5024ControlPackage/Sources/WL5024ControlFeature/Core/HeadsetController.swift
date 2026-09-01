import Foundation

@MainActor
public protocol HeadsetController: AnyObject {
    func events() async -> AsyncStream<HeadsetEvent>
    func start() async
    func stop() async
    func refresh() async throws -> HeadsetSnapshot
    func set(_ key: HeadsetSettingKey, value: SettingValue) async throws -> HeadsetSnapshot
    func perform(_ key: HeadsetSettingKey) async throws -> HeadsetSnapshot
}
