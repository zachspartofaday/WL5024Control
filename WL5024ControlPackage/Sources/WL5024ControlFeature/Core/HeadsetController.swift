import Foundation

@MainActor
public protocol HeadsetController: AnyObject {
    func events() async -> AsyncStream<HeadsetEvent>
    func start() async -> HeadsetStateUpdate
    func stop() async -> HeadsetStateUpdate
    func refresh() async throws -> HeadsetStateUpdate
    func set(_ key: HeadsetSettingKey, value: SettingValue) async throws -> HeadsetStateUpdate
    func perform(_ key: HeadsetSettingKey) async throws -> HeadsetStateUpdate
    func discoverReadOnly(
        progress: @escaping @MainActor @Sendable (ReadOnlyDiscoveryProgress) -> Void
    ) async throws -> ReadOnlyDiscoveryResult
}
