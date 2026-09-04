import Foundation

public struct ReadOnlyDiscoveryProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let currentProbe: String

    public init(completed: Int, total: Int, currentProbe: String) {
        self.completed = completed
        self.total = total
        self.currentProbe = currentProbe
    }
}

public struct ReadOnlyDiscoverySummary: Sendable, Equatable {
    public let queryCount: Int
    public let responseCount: Int
    public let timeoutCount: Int
    public let failureCount: Int
    public let decodedSettingCount: Int
    public let elapsedSeconds: Double

    public init(
        queryCount: Int,
        responseCount: Int,
        timeoutCount: Int,
        failureCount: Int,
        decodedSettingCount: Int,
        elapsedSeconds: Double
    ) {
        self.queryCount = queryCount
        self.responseCount = responseCount
        self.timeoutCount = timeoutCount
        self.failureCount = failureCount
        self.decodedSettingCount = decodedSettingCount
        self.elapsedSeconds = elapsedSeconds
    }
}

public struct ReadOnlyDiscoveryResult: Sendable, Equatable {
    public let update: HeadsetStateUpdate
    public let summary: ReadOnlyDiscoverySummary

    public init(update: HeadsetStateUpdate, summary: ReadOnlyDiscoverySummary) {
        self.update = update
        self.summary = summary
    }
}

public enum ReadOnlyDiscoveryState: Sendable, Equatable {
    case idle
    case running
    case completed
    case cancelled
    case failed(String)
}

struct ReadOnlyProbe: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case preference(module: UInt16)
        case wearDetection
        case setting(HeadsetSettingKey)
        case environmentDetection
        case smartSwitch
    }

    let identifier: String
    let kind: Kind
    let transaction: TransportTransaction
    let timeout: Duration
}

enum ReadOnlyDiscoveryPlan {
    /// Preference module identifiers observed in Dell's SDK are one byte wide. Scanning the
    /// complete byte range through the recovered getter is exhaustive without inventing opcodes.
    static let preferenceModules: ClosedRange<UInt16> = 0...255
    static let probeTimeout: Duration = .milliseconds(750)

    static let probes: [ReadOnlyProbe] = preferenceModules.map { module in
        ReadOnlyProbe(
            identifier: "preference.module.\(module)",
            kind: .preference(module: module),
            transaction: WL5024Command.getPreference(module: module).transaction,
            timeout: probeTimeout
        )
    } + [
        ReadOnlyProbe(
            identifier: "wear-detection",
            kind: .wearDetection,
            transaction: WL5024Command.getWearDetection.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "busy-light",
            kind: .setting(.busyLight),
            transaction: WL5024Command.getBusyLight.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "voice-guidance",
            kind: .setting(.voiceGuidance),
            transaction: WL5024Command.getVoiceGuidance.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "incoming-audio-noise-cancellation",
            kind: .setting(.incomingAudioNoiseCancellation),
            transaction: WL5024Command.getIncomingAudioNoiseCancellation.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "microphone-noise-cancellation",
            kind: .setting(.microphoneNoiseCancellation),
            transaction: WL5024Command.getMicrophoneNoiseCancellation.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "environment-detection",
            kind: .environmentDetection,
            transaction: WL5024Command.getEnvironmentDetection.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "smart-switch",
            kind: .smartSwitch,
            transaction: WL5024Command.getSmartSwitch.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "firmware-v4.mic-flip-action",
            kind: .setting(.micFlipAction),
            transaction: WL5024Command.getMicFlipAction.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "firmware-v4.uc-profile",
            kind: .setting(.ucProfile),
            transaction: WL5024Command.getUCProfile.transaction,
            timeout: probeTimeout
        ),
        ReadOnlyProbe(
            identifier: "firmware-v4.uc-app-status",
            kind: .setting(.ucAppStatus),
            transaction: WL5024Command.getUCAppStatus.transaction,
            timeout: probeTimeout
        ),
    ]
}
