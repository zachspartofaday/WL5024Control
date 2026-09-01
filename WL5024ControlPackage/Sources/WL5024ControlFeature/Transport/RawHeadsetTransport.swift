import Foundation

@MainActor
protocol RawHeadsetTransport: AnyObject {
    var kind: TransportKind { get }
    var isReady: Bool { get }
    func start()
    func stop()
    func transact(_ request: Data, timeout: Duration) async throws -> Data
}
