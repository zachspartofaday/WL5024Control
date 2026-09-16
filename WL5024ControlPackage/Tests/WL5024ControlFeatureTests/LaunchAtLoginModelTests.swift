import Foundation
import Testing
@testable import WL5024ControlFeature

@MainActor
struct LaunchAtLoginModelTests {
    @Test func reflectsStatusAndRegistersOrUnregisters() {
        let service = TestLaunchAtLoginService(status: .disabled)
        let model = LaunchAtLoginModel(service: service)
        #expect(model.state == .disabled)

        model.setEnabled(true)
        #expect(service.registerCallCount == 1)
        #expect(model.state == .enabled)

        model.setEnabled(false)
        #expect(service.unregisterCallCount == 1)
        #expect(model.state == .disabled)
    }

    @Test func exposesApprovalAndOpensSystemSettings() {
        let service = TestLaunchAtLoginService(status: .requiresApproval)
        let model = LaunchAtLoginModel(service: service)
        #expect(model.state == .requiresApproval)

        model.openSystemSettings()
        #expect(service.openSettingsCallCount == 1)
    }

    @Test func preservesRegistrationFailureForRecovery() {
        let service = TestLaunchAtLoginService(status: .disabled)
        service.error = TestError.denied
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(true)
        #expect(model.state == .disabled)
        #expect(model.operationFailure?.contains("denied") == true)

        service.error = nil
        model.refresh()
        #expect(model.state == .disabled)
        #expect(model.operationFailure == nil)
    }

    @Test func preservesEnabledStateAndRetryDirectionWhenUnregisterFails() {
        let service = TestLaunchAtLoginService(status: .enabled)
        service.error = TestError.denied
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(false)
        #expect(model.state == .enabled)
        #expect(model.isEnabled)
        #expect(model.operationFailure?.contains("denied") == true)
        #expect(service.unregisterCallCount == 1)
        #expect(service.registerCallCount == 0)

        service.error = nil
        model.setEnabled(false)
        #expect(model.state == .disabled)
        #expect(service.unregisterCallCount == 2)
        #expect(service.registerCallCount == 0)
    }
}

@MainActor
private final class TestLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginServiceStatus
    var error: Error?
    var registerCallCount = 0
    var unregisterCallCount = 0
    var openSettingsCallCount = 0

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let error { throw error }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let error { throw error }
        status = .disabled
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}

private enum TestError: LocalizedError {
    case denied

    var errorDescription: String? { "Registration denied" }
}
