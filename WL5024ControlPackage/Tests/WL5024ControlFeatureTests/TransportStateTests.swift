import Foundation
import Testing
@testable import WL5024ControlFeature

struct TransportStateTests {
    @Test func bluetoothLifecycleTransitions() {
        #expect(BluetoothLifecyclePolicy.next(after: .startScanning) == .scanning)
        #expect(BluetoothLifecyclePolicy.next(after: .discoveredPeripheral) == .connecting)
        #expect(BluetoothLifecyclePolicy.next(after: .connected) == .discovering)
        #expect(BluetoothLifecyclePolicy.next(after: .discoveredCharacteristics) == .subscribing)
        #expect(BluetoothLifecyclePolicy.next(after: .notificationsEnabled) == .ready)
        #expect(BluetoothLifecyclePolicy.next(after: .setupFailed) == .retrying)
        #expect(BluetoothLifecyclePolicy.next(after: .stop) == .stopped)
    }

    @Test func receiverRemovalDoesNotDisconnectBluetooth() {
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, receiverDetected: true)
        )
        TransportStateReducer.apply(.receiverRemoved, to: &snapshot)
        #expect(snapshot.connection == .connected(.bluetooth))
        #expect(snapshot.device.transport == .bluetooth)
        #expect(!snapshot.device.receiverDetected)
    }

    @Test func bluetoothLossFallsBackToDetectedReceiver() {
        let session = UUID()
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, receiverDetected: true, bluetoothSessionId: session)
        )
        TransportStateReducer.apply(.bluetoothDisconnected(identifier: session), to: &snapshot)
        #expect(snapshot.connection == .qualificationRequired(.receiver))
        #expect(snapshot.device.transport == .receiver)
    }

    @Test func bluetoothDisconnectInvalidatesLiveValues() {
        let session = UUID()
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, bluetoothSessionId: session),
            values: [.busyLight: .boolean(true)],
            readiness: [.busyLight: .experimental],
            valueConfidence: [.busyLight: .deviceConfirmed],
            lastUpdated: .now
        )
        TransportStateReducer.apply(.bluetoothDisconnected(identifier: session), to: &snapshot)
        #expect(snapshot.connection == .searching)
        #expect(snapshot.device.transport == nil)
        #expect(snapshot.device.bluetoothSessionId == nil)
        #expect(snapshot.values.isEmpty)
        #expect(snapshot.valueConfidence.isEmpty)
        #expect(snapshot.lastUpdated == nil)
    }

    @Test func bluetoothReconnectWithDifferentIdentifierInvalidates() {
        let first = UUID()
        let second = UUID()
        var snapshot = HeadsetSnapshot(
            connection: .searching,
            device: .init(transport: nil, bluetoothSessionId: first),
            values: [.busyLight: .boolean(true)],
            valueConfidence: [.busyLight: .deviceConfirmed],
            lastUpdated: .now
        )
        TransportStateReducer.apply(.connectedBluetooth(name: "WL5024", identifier: second), to: &snapshot)
        #expect(snapshot.connection == .connected(.bluetooth))
        #expect(snapshot.device.bluetoothSessionId == second)
        #expect(snapshot.values.isEmpty)
        #expect(snapshot.valueConfidence.isEmpty)
    }

    @Test func staleDisconnectForOldSessionIsIgnored() {
        let current = UUID()
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, bluetoothSessionId: current),
            values: [.busyLight: .boolean(true)],
            valueConfidence: [.busyLight: .deviceConfirmed]
        )
        TransportStateReducer.apply(.bluetoothDisconnected(identifier: UUID()), to: &snapshot)
        #expect(snapshot.connection == .connected(.bluetooth))
        #expect(snapshot.values[.busyLight] == .boolean(true))
    }

    @Test func terminalFailureWhileConnectedInvalidatesLiveValuesWithoutFallback() {
        let session = UUID()
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, bluetoothSessionId: session),
            values: [.busyLight: .boolean(true)],
            valueConfidence: [.busyLight: .deviceConfirmed]
        )
        TransportStateReducer.apply(.failed(source: .bluetooth, message: "gone", willRetry: false), to: &snapshot)
        #expect(snapshot.connection == .failed)
        #expect(snapshot.device.transport == nil)
        #expect(snapshot.device.bluetoothSessionId == nil)
        #expect(snapshot.values.isEmpty)
    }

    @Test func terminalBluetoothFailureWhileConnectedFallsBackToDetectedReceiver() {
        let session = UUID()
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(
                transport: .bluetooth,
                receiverDetected: true,
                bluetoothSessionId: session
            ),
            values: [.busyLight: .boolean(true)],
            readiness: [.busyLight: .experimental],
            valueConfidence: [.busyLight: .deviceConfirmed],
            lastUpdated: .now
        )

        TransportStateReducer.apply(
            .failed(source: .bluetooth, message: "gone", willRetry: false),
            to: &snapshot
        )

        #expect(snapshot.connection == .qualificationRequired(.receiver))
        #expect(snapshot.device.transport == .receiver)
        #expect(snapshot.device.bluetoothSessionId == nil)
        #expect(snapshot.values.isEmpty)
        #expect(snapshot.lastUpdated == nil)
    }

    @Test @MainActor func controllerStopInvalidatesSessionValues() async throws {
        let response = wearResponse(flags: 0x0067)
        let transport = FakeHeadsetTransport(
            responses: Array(repeating: .success(response), count: ShippingWriteQualifications.orderedKeys.count)
        )
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()
        _ = try await controller.refresh()
        #expect(controller.currentSnapshot.values[.busyLight] != nil || controller.currentSnapshot.values[.wearDetection] != nil)
        _ = await controller.stop()
        #expect(controller.currentSnapshot.values.isEmpty)
        #expect(controller.currentSnapshot.valueConfidence.isEmpty)
        #expect(controller.currentSnapshot.device.bluetoothSessionId == nil)
    }

    @Test @MainActor func refreshFailureThrowsWithoutMarkingDataFresh() async {
        let transport = FakeHeadsetTransport(responses: [.failure(HeadsetError.timeout)])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        await #expect(throws: HeadsetError.timeout) { try await controller.refresh() }
        #expect(controller.currentSnapshot.lastUpdated == nil)
        #expect(controller.currentSnapshot.lastAttemptedAt != nil)
        #expect(transport.transactions == Array(
            repeating: WL5024Command.getWearDetection.transaction,
            count: 1
        ) + [
            WL5024Command.getPreference(module: 1).transaction,
            WL5024Command.getEnvironmentDetection.transaction,
            WL5024Command.getMicrophoneNoiseCancellation.transaction,
            WL5024Command.getPreference(module: 7).transaction,
            WL5024Command.getBusyLight.transaction,
            WL5024Command.getVoiceGuidance.transaction,
            WL5024Command.getSmartSwitch.transaction,
            WL5024Command.getMicFlipAction.transaction,
            WL5024Command.getUCProfile.transaction,
            WL5024Command.getUCAppStatus.transaction,
            WL5024Command.getLEAudioFeatureMode.transaction,
        ])
    }

    @Test @MainActor func failedRefreshPublishesInvalidationAfterEarlierSuccess() async throws {
        let transport = FakeHeadsetTransport(responses: completeRefreshResponses(wearFlags: 0x0067))
        let controller = LiveHeadsetController(transport: transport)
        let model = HeadsetModel(demoMode: false, controller: controller)
        await model.start()
        for _ in 0..<100 where model.snapshot.connection != .connected(.bluetooth) {
            await Task.yield()
        }

        await model.refresh().value
        #expect(model.snapshot.confidence(for: .busyLight) == .deviceConfirmed)
        #expect(model.snapshot.lastUpdated != nil)

        // The fake has no responses left, so every distinct read now fails.
        await model.refresh().value
        for _ in 0..<100 where !model.snapshot.values.isEmpty {
            await Task.yield()
        }

        #expect(model.snapshot.values.isEmpty)
        #expect(model.snapshot.valueConfidence.isEmpty)
        #expect(model.snapshot.lastUpdated == nil)
        #expect(model.snapshot.lastAttemptedAt != nil)
        #expect(model.failure != nil)
        await model.stop()
    }

    @Test @MainActor func cancellationStopsRefreshImmediately() async {
        let transport = FakeHeadsetTransport(responses: [.failure(CancellationError())])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        await #expect(throws: CancellationError.self) { try await controller.refresh() }
        #expect(transport.transactions == [WL5024Command.getWearDetection.transaction])
        #expect(controller.currentSnapshot.lastUpdated == nil)
    }

    @Test @MainActor func refreshDecodesRecoveredCompositeSettings() async throws {
        let response = wearResponse(flags: 0x0067)
        let transport = FakeHeadsetTransport(
            responses: Array(repeating: .success(response), count: ShippingWriteQualifications.orderedKeys.count)
        )
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        let snapshot = (try await controller.refresh()).snapshot
        #expect(snapshot.values[.wearDetection] == .boolean(true))
        #expect(snapshot.values[.automaticMedia] == .boolean(true))
        #expect(snapshot.values[.muteMicrophoneOnRemoval] == .boolean(true))
        #expect(snapshot.values[.quickPause] == .boolean(true))
        #expect(snapshot.values[.quickPauseSensitivity] == .choice("sensitive"))
        #expect(snapshot.values[.answerCallsOnWear] == .boolean(true))
        #expect(snapshot.confidence(for: .automaticMedia) == .deviceConfirmed)
        #expect(snapshot.readiness(for: .automaticMedia) == .experimental)
        #expect(snapshot.lastUpdated != nil)
    }

    @Test @MainActor func qualifiedWriteReadsCurrentFlagsThenAcknowledgesAndReadsBack() async throws {
        let current = wearResponse(flags: 0x0067)
        let acknowledgement = wearAcknowledgement(status: 0)
        let readback = wearResponse(flags: 0x0065)
        let transport = FakeHeadsetTransport(responses: [
            .success(current), .success(acknowledgement), .success(readback),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        let snapshot = (try await controller.set(.automaticMedia, value: .boolean(false))).snapshot
        #expect(snapshot.values[.automaticMedia] == .boolean(false))
        #expect(snapshot.values[.quickPause] == .boolean(true))
        #expect(snapshot.values[.quickPauseSensitivity] == .choice("sensitive"))
        #expect(transport.transactions == [
            WL5024Command.getWearDetection.transaction,
            WL5024Command.setWearDetection(0x0065).transaction,
            WL5024Command.getWearDetection.transaction,
        ])
    }

    @Test @MainActor func readbackMismatchDoesNotPublishRequestedValue() async {
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x0067)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0067)),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        await #expect(throws: HeadsetError.readbackMismatch(.automaticMedia)) {
            try await controller.set(.automaticMedia, value: .boolean(false))
        }
        // The requested value is never claimed, but the observed composite
        // remains authoritative even though the command reports mismatch.
        #expect(controller.currentSnapshot.values[.automaticMedia] == .boolean(true))
        #expect(controller.currentSnapshot.confidence(for: .automaticMedia) == .deviceConfirmed)
        #expect(controller.currentSnapshot.lastUpdated != nil)
    }

    @Test @MainActor func negativeAcknowledgementStopsBeforeReadbackAndPreservesConfirmedValue() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x0000)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0002)),
            .success(wearResponse(flags: 0x0002)),
            .success(wearAcknowledgement(status: 1)),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        _ = try await controller.set(.automaticMedia, value: .boolean(true))
        await #expect(throws: HeadsetError.commandRejected) {
            try await controller.set(.automaticMedia, value: .boolean(false))
        }
        #expect(transport.transactions.count == 5)
        #expect(controller.currentSnapshot.values[.automaticMedia] == .boolean(true))
        #expect(controller.currentSnapshot.confidence(for: .automaticMedia) == .deviceConfirmed)
    }

    @Test @MainActor func malformedFirstAcknowledgementReadsBackAppliedState() async throws {
        let malformedAcknowledgement = RaceFrame(
            packetType: .response,
            opcode: 0x0020,
            payload: Data([0, 0])
        ).encoded
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x0000)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0002)),
            .success(wearResponse(flags: 0x0002)),
            .success(malformedAcknowledgement),
            .success(wearResponse(flags: 0x0000)),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        _ = try await controller.set(.automaticMedia, value: .boolean(true))
        await #expect(throws: HeadsetError.transport(
            "The automaticMedia change could not be confirmed (observed boolean(false)). Check the setting and try again."
        )) {
            try await controller.set(.automaticMedia, value: .boolean(false))
        }
        #expect(transport.transactions.count == 6)
        #expect(controller.currentSnapshot.values[.automaticMedia] == .boolean(false))
        #expect(controller.currentSnapshot.confidence(for: .automaticMedia) == .deviceConfirmed)
    }

    @Test func shippingRegistryContainsOnlyCompleteRecoveredBluetoothContracts() {
        #expect(ShippingWriteQualifications.orderedKeys == CapabilityCatalog.experimentalSettings)
        #expect(Set(ShippingWriteQualifications.all.keys) == Set(CapabilityCatalog.experimentalSettings))
        let visibleReadKeys = CapabilityCatalog.configurableSettings + CapabilityCatalog.readOnlySettings
        #expect(Set(ShippingSettingReads.all.keys) == Set(visibleReadKeys))
        for key in [
            HeadsetSettingKey.wearDetection,
            .automaticMedia,
            .muteMicrophoneOnRemoval,
            .quickPause,
            .quickPauseSensitivity,
            .answerCallsOnWear,
        ] {
            let qualification = ShippingWriteQualifications.all[key]
            #expect(qualification?.preparationTransactions == [WL5024Command.getWearDetection.transaction])
            #expect(qualification?.readBackTransactions == [WL5024Command.getWearDetection.transaction])
            #expect(qualification?.provenance.captureIdentifier == "dell-ddpm-2.3.0.9-static-2026-09-01")
        }
        #expect(ShippingWriteQualifications.all[.sidetone]?.readBackTransactions == [
            WL5024Command.getPreference(module: 7).transaction,
            WL5024Command.getPreference(module: 6).transaction,
        ])
        #expect(ShippingWriteQualifications.all[.advancedPassthrough] == nil)
        #expect(ShippingWriteQualifications.all[.autoPowerOff] == nil)
        #expect(ShippingWriteQualifications.all[.incomingAudioNoiseCancellation] == nil)
        #expect(ShippingWriteQualifications.all[.voicePrompts] == nil)
        #expect(ShippingWriteQualifications.all[.voiceGuidance]?.readBackTransactions == [
            WL5024Command.getVoiceGuidance.transaction,
        ])
    }

    @Test func automaticMediaContractPreservesAdjacentFlags() throws {
        let qualification = try #require(ShippingWriteQualifications.all[.automaticMedia])
        let transactions = try qualification.writeTransactions(
            for: .boolean(false),
            preparationResponses: [wearResponse(flags: 0xA567)]
        )
        #expect(transactions == [WL5024Command.setWearDetection(0xA565).transaction])
        #expect(try qualification.readBackDecoder([wearResponse(flags: 0xA565)]) == .boolean(false))
    }

    @Test func sidetoneContractWritesStateThenLevelAndReadsBoth() throws {
        let qualification = try #require(ShippingWriteQualifications.all[.sidetone])
        #expect(try qualification.writeTransactions(for: .choice("off")) == [
            WL5024Command.setPreferenceByte(module: 7, value: 0).transaction,
        ])
        #expect(try qualification.writeTransactions(for: .choice("5")) == [
            WL5024Command.setPreferenceByte(module: 7, value: 1).transaction,
            WL5024Command.setPreferenceUInt16(module: 6, value: 5).transaction,
        ])
        #expect(try qualification.readBackDecoder([
            preferenceResponse(module: 7, value: [0]),
            preferenceResponse(module: 6, value: [5, 0]),
        ]) == .choice("off"))
        #expect(try qualification.readBackDecoder([
            preferenceResponse(module: 7, value: [1]),
            preferenceResponse(module: 6, value: [5, 0]),
        ]) == .choice("5"))
    }

    @Test func automaticPowerOffCaptureIsReadOnlyAndDecodesBothProfiles() throws {
        let definition = try #require(ShippingSettingReads.all[.autoPowerOff])
        #expect(try definition.decoder([
            preferenceResponse(module: 1, value: [1, 0, 0x08, 0x07, 0, 0, 0x08, 0x07]),
        ]) == .choice("30m"))
        #expect(ShippingWriteQualifications.all[.autoPowerOff] == nil)
    }

    @Test @MainActor func refreshDecodesBuildNineCaptureAndGatesUnqualifiedWrites() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x000F)),
            .success(preferenceResponse(module: 1, value: [1, 0, 0x08, 0x07, 0, 0, 0x08, 0x07])),
            .success(environmentDetectionResponse(false)),
            .success(booleanResponse(opcode: 0x0EFF, value: true)),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [3, 0])),
            .success(booleanResponse(opcode: 0x0023, value: true)),
            .success(booleanResponse(opcode: 0x0025, value: true)),
            .success(smartSwitchResponse(false)),
            .success(statusByteResponse(opcode: 0x0029, value: 3)),
            .success(statusByteResponse(opcode: 0x0041, value: 0)),
            .success(statusByteResponse(opcode: 0x0042, value: 0)),
            .success(preferenceResponse(module: 0x0031, value: [1, 2, 2, 0])),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        let snapshot = (try await controller.refresh()).snapshot
        #expect(snapshot.values[.autoPowerOff] == .choice("30m"))
        #expect(snapshot.readiness(for: .autoPowerOff) == .readOnly)
        #expect(snapshot.values[.environmentDetection] == .boolean(false))
        #expect(snapshot.readiness(for: .environmentDetection) == .readOnly)
        #expect(snapshot.values[.sidetone] == .choice("3"))
        #expect(snapshot.values[.microphoneNoiseCancellation] == .boolean(true))
        #expect(snapshot.readiness(for: .microphoneNoiseCancellation) == .experimental)
        #expect(snapshot.values[.smartSwitch] == .boolean(false))
        #expect(snapshot.readiness(for: .smartSwitch) == .readOnly)
        #expect(snapshot.values[.micFlipAction] == .integer(3))
        #expect(snapshot.values[.ucProfile] == .integer(0))
        #expect(snapshot.values[.ucAppStatus] == .integer(0))
        #expect(snapshot.values[.leAudioFeatureMode] == .integer(2))
        #expect(snapshot.readiness(for: .leAudioFeatureMode) == .readOnly)
        #expect(snapshot.readiness(for: .advancedPassthrough) == .validationPending)
        #expect(snapshot.readiness(for: .incomingAudioNoiseCancellation) == .validationPending)
        await #expect(throws: HeadsetError.unsupported(.autoPowerOff)) {
            try await controller.set(.autoPowerOff, value: .choice("30m"))
        }
        #expect(transport.transactions.count == 13)
    }

    @Test @MainActor func sidetoneWriteValidatesBothAcknowledgementsAndBothReadbacks() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(preferenceAcknowledgement(module: 7)),
            .success(preferenceAcknowledgement(module: 6)),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [5, 0])),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        let update = try await controller.set(.sidetone, value: .choice("5"))
        #expect(update.snapshot.values[.sidetone] == .choice("5"))
        #expect(transport.transactions == [
            WL5024Command.setPreferenceByte(module: 7, value: 1).transaction,
            WL5024Command.setPreferenceUInt16(module: 6, value: 5).transaction,
            WL5024Command.getPreference(module: 7).transaction,
            WL5024Command.getPreference(module: 6).transaction,
        ])
    }

    @Test @MainActor func readOnlyDiscoveryDecodesCompositeAndSmartSwitchGetters() async throws {
        let responses: [Result<Data, any Error>] = (0...265).map { index in
            switch index {
            case 49: .success(preferenceResponse(module: 0x0031, value: [1, 2, 2, 0]))
            case 256: .success(wearResponse(flags: 0x0067))
            case 262: .success(smartSwitchResponse(false))
            default: .failure(HeadsetError.timeout)
            }
        }
        let transport = FakeHeadsetTransport(responses: responses)
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()
        var finalProgress: ReadOnlyDiscoveryProgress?

        let result = try await controller.discoverReadOnly { finalProgress = $0 }
        #expect(transport.transactions == ReadOnlyDiscoveryPlan.probes.map(\.transaction))
        #expect(result.summary.queryCount == 266)
        #expect(result.summary.responseCount == 3)
        #expect(result.summary.timeoutCount == 263)
        #expect(result.summary.decodedSettingCount == 8)
        #expect(result.update.snapshot.values[.automaticMedia] == .boolean(true))
        #expect(result.update.snapshot.values[.smartSwitch] == .boolean(false))
        #expect(result.update.snapshot.values[.leAudioFeatureMode] == .integer(2))
        #expect(finalProgress?.completed == 266)
    }

    @Test @MainActor func partialRefreshRemovesFailedKeysSharingNoTransaction() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x0067)),
            .failure(HeadsetError.timeout),
            .success(environmentDetectionResponse(true)),
            .success(booleanResponse(opcode: 0x0EFF, value: true)),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [3, 0])),
            .success(booleanResponse(opcode: 0x0023, value: true)),
            .success(booleanResponse(opcode: 0x0025, value: true)),
            .success(smartSwitchResponse(true)),
            .success(statusByteResponse(opcode: 0x0029, value: 3)),
            .success(statusByteResponse(opcode: 0x0041, value: 1)),
            .success(statusByteResponse(opcode: 0x0042, value: 2)),
            .success(preferenceResponse(module: 0x0031, value: [1, 2, 2, 0])),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        let snapshot = (try await controller.refresh()).snapshot
        // Wear shares one cached transaction: all six succeed together.
        #expect(snapshot.values[.wearDetection] == .boolean(true))
        #expect(snapshot.confidence(for: .wearDetection) == .deviceConfirmed)
        // Failed autoPowerOff is removed, not left as stale confirmed.
        #expect(snapshot.values[.autoPowerOff] == nil)
        #expect(snapshot.confidence(for: .autoPowerOff) == .unknown)
        #expect(snapshot.readiness(for: .autoPowerOff) == .unavailable)
        // Unrelated successes still confirm and advance freshness.
        #expect(snapshot.values[.environmentDetection] == .boolean(true))
        #expect(snapshot.lastUpdated != nil)
    }

    @Test @MainActor func failedWearTransactionInvalidatesAllSixWearKeys() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .failure(HeadsetError.timeout),
            .success(preferenceResponse(module: 1, value: [1, 0, 0x08, 0x07, 0, 0, 0x08, 0x07])),
            .success(environmentDetectionResponse(false)),
            .success(booleanResponse(opcode: 0x0EFF, value: false)),
            .success(preferenceResponse(module: 7, value: [0])),
            .success(preferenceResponse(module: 6, value: [0, 0])),
            .success(booleanResponse(opcode: 0x0023, value: false)),
            .success(booleanResponse(opcode: 0x0025, value: false)),
            .success(smartSwitchResponse(false)),
            .success(statusByteResponse(opcode: 0x0029, value: 3)),
            .success(statusByteResponse(opcode: 0x0041, value: 0)),
            .success(statusByteResponse(opcode: 0x0042, value: 0)),
            .success(preferenceResponse(module: 0x0031, value: [1, 2, 2, 0])),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        let snapshot = (try await controller.refresh()).snapshot
        for key in ShippingWriteQualifications.wearKeys {
            #expect(snapshot.values[key] == nil, "wear key \(key) should be removed")
            #expect(snapshot.confidence(for: key) == .unknown)
        }
        #expect(snapshot.values[.autoPowerOff] != nil)
        #expect(snapshot.lastUpdated != nil)
    }

    @Test func preConnectionTerminalFailureWithoutFallbackBecomesFailed() {
        var snapshot = HeadsetSnapshot(connection: .searching, device: .init(transport: nil))
        TransportStateReducer.apply(.failed(source: .bluetooth, message: "no service", willRetry: false), to: &snapshot)
        #expect(snapshot.connection == .failed)
    }

    @Test func preConnectionTerminalBluetoothFailurePreservesReceiverFallback() {
        var snapshot = HeadsetSnapshot(
            connection: .qualificationRequired(.receiver),
            device: .init(transport: .receiver, receiverDetected: true)
        )

        TransportStateReducer.apply(
            .failed(source: .bluetooth, message: "no service", willRetry: false),
            to: &snapshot
        )

        #expect(snapshot.connection == .qualificationRequired(.receiver))
        #expect(snapshot.device.transport == .receiver)
    }

    @Test func terminalReceiverFailureDoesNotDisconnectBluetooth() {
        let session = UUID()
        var snapshot = HeadsetSnapshot(
            connection: .connected(.bluetooth),
            device: .init(transport: .bluetooth, bluetoothSessionId: session)
        )

        TransportStateReducer.apply(
            .failed(source: .receiver, message: "monitor unavailable", willRetry: false),
            to: &snapshot
        )

        #expect(snapshot.connection == .connected(.bluetooth))
        #expect(snapshot.device.transport == .bluetooth)
        #expect(snapshot.device.bluetoothSessionId == session)
    }

    @Test func retryingPreConnectionFailureStaysSearching() {
        var snapshot = HeadsetSnapshot(connection: .searching, device: .init(transport: nil))
        TransportStateReducer.apply(.failed(source: .bluetooth, message: "retry", willRetry: true), to: &snapshot)
        #expect(snapshot.connection == .searching)
    }

    @Test @MainActor func sensitivityWriteWhileQuickPauseOffCannotDiverge() async throws {
        // Establish a confirmed enabled value, then observe mode 0 during the
        // rejected sensitivity preparation. The observed composite state must
        // replace every stale wear projection even though no write follows.
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x0010)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0020)),
            .success(wearResponse(flags: 0x0000)),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        let enabled = try await controller.set(.quickPause, value: .boolean(true)).snapshot
        #expect(enabled.values[.quickPause] == .boolean(true))

        await #expect(throws: HeadsetError.invalidValue(.quickPauseSensitivity)) {
            try await controller.set(.quickPauseSensitivity, value: .choice("sensitive"))
        }
        #expect(transport.transactions == [
            WL5024Command.getWearDetection.transaction,
            WL5024Command.setWearDetection(0x0010).transaction,
            WL5024Command.getWearDetection.transaction,
            WL5024Command.getWearDetection.transaction,
        ])
        #expect(controller.currentSnapshot.values[.quickPauseSensitivity] == .choice("normal"))
        #expect(controller.currentSnapshot.values[.quickPause] == .boolean(false))
        for key in ShippingWriteQualifications.wearKeys {
            #expect(controller.currentSnapshot.confidence(for: key) == .deviceConfirmed)
        }
    }

    @Test @MainActor func quickPauseTogglePublishesAllCompositeProjections() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x0010)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0010)),
            .success(wearResponse(flags: 0x0010)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0000)),
            .success(wearResponse(flags: 0x0000)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0020)),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        var snapshot = try await controller.set(.quickPause, value: .boolean(true)).snapshot
        #expect(snapshot.values[.quickPause] == .boolean(true))
        #expect(snapshot.values[.quickPauseSensitivity] == .choice("normal"))

        snapshot = try await controller.set(.quickPause, value: .boolean(false)).snapshot
        #expect(snapshot.values[.quickPause] == .boolean(false))
        #expect(snapshot.values[.quickPauseSensitivity] == .choice("normal"))

        snapshot = try await controller.set(.quickPause, value: .boolean(true)).snapshot
        #expect(snapshot.values[.quickPause] == .boolean(true))
        #expect(snapshot.values[.quickPauseSensitivity] == .choice("sensitive"))
        for key in ShippingWriteQualifications.wearKeys {
            #expect(snapshot.confidence(for: key) == .deviceConfirmed)
        }
    }

    @Test @MainActor func sidetoneSecondStepFailureReportsPartialState() async {
        let transport = FakeHeadsetTransport(responses: [
            .success(preferenceAcknowledgement(module: 7)),
            .failure(HeadsetError.timeout),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [2, 0])),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        await #expect(throws: HeadsetError.transport("Part of the sidetone change was applied (observed choice(\"2\")). Check the setting and try again.")) {
            try await controller.set(.sidetone, value: .choice("5"))
        }
        // Observed partial state published; no rollback writes issued.
        #expect(controller.currentSnapshot.values[.sidetone] == .choice("2"))
        #expect(controller.currentSnapshot.confidence(for: .sidetone) == .deviceConfirmed)
        #expect(transport.transactions == [
            WL5024Command.setPreferenceByte(module: 7, value: 1).transaction,
            WL5024Command.setPreferenceUInt16(module: 6, value: 5).transaction,
            WL5024Command.getPreference(module: 7).transaction,
            WL5024Command.getPreference(module: 6).transaction,
        ])
    }

    @Test @MainActor func unreadablePartialSidetoneStateInvalidatesEarlierValue() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(preferenceAcknowledgement(module: 7)),
            .success(preferenceAcknowledgement(module: 6)),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [2, 0])),
            .success(preferenceAcknowledgement(module: 7)),
            .failure(HeadsetError.timeout),
            .failure(HeadsetError.timeout),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        _ = try await controller.set(.sidetone, value: .choice("2"))
        #expect(controller.currentSnapshot.values[.sidetone] == .choice("2"))

        await #expect(throws: HeadsetError.transport(
            "Part of the sidetone change may have been applied, but its current value could not be read. Refresh or reconnect before trying again."
        )) {
            try await controller.set(.sidetone, value: .choice("5"))
        }
        #expect(controller.currentSnapshot.values[.sidetone] == nil)
        #expect(controller.currentSnapshot.confidence(for: .sidetone) == .unknown)
        #expect(controller.currentSnapshot.readiness(for: .sidetone) == .experimental)
    }

    @Test @MainActor func sidetonePreDispatchFirstStepFailurePreservesConfirmedValue() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(preferenceAcknowledgement(module: 7)),
            .success(preferenceAcknowledgement(module: 6)),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [2, 0])),
            .failure(HeadsetError.timeout),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        _ = try await controller.set(.sidetone, value: .choice("2"))
        await #expect(throws: HeadsetError.timeout) {
            try await controller.set(.sidetone, value: .choice("5"))
        }
        #expect(transport.transactions.count == 5)
        #expect(controller.currentSnapshot.values[.sidetone] == .choice("2"))
        #expect(controller.currentSnapshot.confidence(for: .sidetone) == .deviceConfirmed)
    }

    @Test @MainActor func sidetoneDispatchedFirstStepFailureReadsBackCurrentValue() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(preferenceAcknowledgement(module: 7)),
            .success(preferenceAcknowledgement(module: 6)),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [2, 0])),
            .failure(DispatchedTransactionError(
                underlying: HeadsetError.timeout,
                gattWriteAcknowledged: true
            )),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [2, 0])),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        _ = try await controller.set(.sidetone, value: .choice("2"))
        await #expect(throws: HeadsetError.transport(
            "The sidetone change could not be confirmed (observed choice(\"2\")). Check the setting and try again."
        )) {
            try await controller.set(.sidetone, value: .choice("5"))
        }
        #expect(controller.currentSnapshot.values[.sidetone] == .choice("2"))
        #expect(controller.currentSnapshot.confidence(for: .sidetone) == .deviceConfirmed)
        #expect(transport.transactions.count == 7)
    }

    @Test @MainActor func dispatchedWriteCancellationInvalidatesConfirmedValue() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(preferenceAcknowledgement(module: 7)),
            .success(preferenceAcknowledgement(module: 6)),
            .success(preferenceResponse(module: 7, value: [1])),
            .success(preferenceResponse(module: 6, value: [2, 0])),
            .failure(DispatchedTransactionError(
                underlying: CancellationError(),
                gattWriteAcknowledged: false
            )),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        _ = try await controller.set(.sidetone, value: .choice("2"))
        await #expect(throws: CancellationError.self) {
            try await controller.set(.sidetone, value: .choice("5"))
        }
        #expect(controller.currentSnapshot.values[.sidetone] == nil)
        #expect(controller.currentSnapshot.confidence(for: .sidetone) == .unknown)
        #expect(controller.currentSnapshot.readiness(for: .sidetone) == .experimental)
        #expect(transport.transactions.count == 5)
    }

    @Test @MainActor func unreadableFirstWearWriteInvalidatesCompositeValues() async throws {
        let transport = FakeHeadsetTransport(responses: [
            .success(wearResponse(flags: 0x0000)),
            .success(wearAcknowledgement(status: 0)),
            .success(wearResponse(flags: 0x0002)),
            .success(wearResponse(flags: 0x0002)),
            .failure(DispatchedTransactionError(
                underlying: HeadsetError.timeout,
                gattWriteAcknowledged: true
            )),
            .failure(HeadsetError.timeout),
        ])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()

        _ = try await controller.set(.automaticMedia, value: .boolean(true))
        await #expect(throws: HeadsetError.transport(
            "The automaticMedia change may have been applied, but its current value could not be read. Refresh or reconnect before trying again."
        )) {
            try await controller.set(.automaticMedia, value: .boolean(false))
        }
        for key in ShippingWriteQualifications.wearKeys {
            #expect(controller.currentSnapshot.values[key] == nil)
            #expect(controller.currentSnapshot.confidence(for: key) == .unknown)
            #expect(controller.currentSnapshot.readiness(for: key) == .experimental)
        }
        #expect(transport.transactions.count == 6)
    }

    @Test @MainActor func readOnlyDiscoveryPropagatesCancellationBeforeSecondQuery() async {
        let transport = FakeHeadsetTransport(responses: [.failure(CancellationError())])
        let controller = LiveHeadsetController(transport: transport)
        _ = await controller.start()
        await #expect(throws: CancellationError.self) {
            try await controller.discoverReadOnly { _ in }
        }
        #expect(transport.transactions.count == 1)
    }
}

@MainActor
private final class FakeHeadsetTransport: HeadsetTransporting {
    private(set) var activeKind: TransportKind? = .bluetooth
    private(set) var transactions: [TransportTransaction] = []
    private var responses: [Result<Data, any Error>]
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?

    init(responses: [Result<Data, any Error>]) { self.responses = responses }

    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler
        updateHandler(.connectedBluetooth(name: "Test WL5024", identifier: UUID()))
    }

    func stop() {
        activeKind = nil
        updateHandler = nil
    }

    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        transactions.append(transaction)
        guard !responses.isEmpty else { throw HeadsetError.timeout }
        return try responses.removeFirst().get()
    }
}

private func completeRefreshResponses(wearFlags: UInt16) -> [Result<Data, any Error>] {
    [
        .success(wearResponse(flags: wearFlags)),
        .success(preferenceResponse(module: 1, value: [1, 0, 0x08, 0x07, 0, 0, 0x08, 0x07])),
        .success(environmentDetectionResponse(false)),
        .success(booleanResponse(opcode: 0x0EFF, value: true)),
        .success(preferenceResponse(module: 7, value: [1])),
        .success(preferenceResponse(module: 6, value: [3, 0])),
        .success(booleanResponse(opcode: 0x0023, value: true)),
        .success(booleanResponse(opcode: 0x0025, value: true)),
        .success(smartSwitchResponse(false)),
        .success(statusByteResponse(opcode: 0x0029, value: 3)),
        .success(statusByteResponse(opcode: 0x0041, value: 0)),
        .success(statusByteResponse(opcode: 0x0042, value: 0)),
        .success(preferenceResponse(module: 0x0031, value: [1, 2, 2, 0])),
    ]
}

private func wearResponse(flags: UInt16) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: 0x0021,
        payload: Data([0, UInt8(truncatingIfNeeded: flags), UInt8(truncatingIfNeeded: flags >> 8)])
    ).encoded
}

private func wearAcknowledgement(status: UInt8) -> Data {
    RaceFrame(packetType: .response, opcode: 0x0020, payload: Data([status])).encoded
}

private func preferenceResponse(module: UInt16, value: [UInt8]) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: 0x2C83,
        payload: Data([
            0,
            UInt8(truncatingIfNeeded: module),
            UInt8(truncatingIfNeeded: module >> 8),
        ] + value)
    ).encoded
}

private func preferenceAcknowledgement(module: UInt16) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: 0x2C82,
        payload: Data([
            0,
            UInt8(truncatingIfNeeded: module),
            UInt8(truncatingIfNeeded: module >> 8),
        ])
    ).encoded
}

private func booleanResponse(opcode: UInt16, value: Bool) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: opcode,
        payload: Data([0, value ? 1 : 0])
    ).encoded
}

private func statusByteResponse(opcode: UInt16, value: UInt8) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: opcode,
        payload: Data([0, value])
    ).encoded
}

private func smartSwitchResponse(_ value: Bool) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: 0x0901,
        payload: Data([0x06, 0x00, 0x00, value ? 1 : 0])
    ).encoded
}

private func environmentDetectionResponse(_ value: Bool) -> Data {
    RaceFrame(
        packetType: .response,
        opcode: 0x0E17,
        payload: Data([0x03, 0x03, value ? 1 : 0])
    ).encoded
}
