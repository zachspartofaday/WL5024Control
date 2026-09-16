import Foundation
import Observation
import ServiceManagement

public enum LaunchAtLoginState: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case updating
    case failed(String)
}

enum LaunchAtLoginServiceStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
@Observable
public final class LaunchAtLoginModel {
    public private(set) var state: LaunchAtLoginState
    public private(set) var operationFailure: String?

    private let service: any LaunchAtLoginServicing

    public convenience init() {
        self.init(service: SystemLaunchAtLoginService())
    }

    public convenience init(mockState: LaunchAtLoginState) {
        self.init(service: MockLaunchAtLoginService(state: mockState))
    }

    init(service: any LaunchAtLoginServicing) {
        self.service = service
        state = .disabled
        refresh()
    }

    public var isEnabled: Bool {
        state == .enabled
    }

    public func setEnabled(_ enabled: Bool) {
        operationFailure = nil
        state = .updating
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
        } catch {
            updateStateFromService()
            operationFailure = error.localizedDescription
        }
    }

    public func refresh() {
        operationFailure = nil
        updateStateFromService()
    }

    private func updateStateFromService() {
        state = switch service.status {
        case .enabled: .enabled
        case .disabled: .disabled
        case .requiresApproval: .requiresApproval
        case .unavailable: .failed("Launch at Login is unavailable for this copy of the app.")
        }
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }
}

@MainActor
private final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginServiceStatus {
        switch service.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
private final class MockLaunchAtLoginService: LaunchAtLoginServicing {
    private var currentStatus: LaunchAtLoginServiceStatus

    init(state: LaunchAtLoginState) {
        currentStatus = switch state {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .disabled, .updating, .failed: .disabled
        }
    }

    var status: LaunchAtLoginServiceStatus { currentStatus }

    func register() throws {
        currentStatus = .enabled
    }

    func unregister() throws {
        currentStatus = .disabled
    }

    func openSystemSettings() {}
}
