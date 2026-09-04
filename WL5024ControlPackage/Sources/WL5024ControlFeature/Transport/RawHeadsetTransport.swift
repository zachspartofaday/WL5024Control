import Foundation

@MainActor
protocol RawHeadsetTransport: AnyObject {
    var kind: TransportKind { get }
    var isReady: Bool { get }
    func configure(updateHandler: @escaping @Sendable (TransportUpdate) -> Void)
    func start()
    func stop()
    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data
}

@MainActor
protocol HeadsetTransporting: AnyObject {
    var activeKind: TransportKind? { get }
    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void)
    func stop()
    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data
}
