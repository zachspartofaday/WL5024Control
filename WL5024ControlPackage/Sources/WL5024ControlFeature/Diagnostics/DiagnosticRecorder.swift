import Foundation

public struct DiagnosticEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: String
    public let message: String
    public let details: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        category: String,
        message: String,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
        self.details = details
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public struct Device: Codable, Equatable, Sendable {
        public let model: String
        public let headsetFirmware: String?
        public let receiverFirmware: String?
        public let batteryPercent: Int?
        public let transport: String?
    }

    public struct Capability: Codable, Equatable, Sendable {
        public let key: String
        public let qualification: String
        public let recipe: String
        public let evidence: String
    }

    public let formatVersion: Int
    public let generatedAt: Date
    public let appVersion: String
    public let operatingSystem: String
    public let privacy: String
    public let device: Device
    public let capabilities: [Capability]
    public let entries: [DiagnosticEntry]

    public init(
        formatVersion: Int,
        generatedAt: Date,
        appVersion: String,
        operatingSystem: String,
        privacy: String,
        device: Device,
        capabilities: [Capability],
        entries: [DiagnosticEntry]
    ) {
        self.formatVersion = formatVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.operatingSystem = operatingSystem
        self.privacy = privacy
        self.device = device
        self.capabilities = capabilities
        self.entries = entries
    }
}

@MainActor
public final class DiagnosticRecorder {
    public static let shared = DiagnosticRecorder()

    private var buffer: FixedCapacityRingBuffer<DiagnosticEntry>

    public var entries: [DiagnosticEntry] { buffer.elements }

    init(maximumEntries: Int = 5_000) {
        buffer = FixedCapacityRingBuffer(capacity: maximumEntries)
    }

    public func record(
        _ category: String,
        _ message: String,
        details: [String: String] = [:]
    ) {
        buffer.append(DiagnosticEntry(category: category, message: message, details: details))
    }

    public func report(snapshot: HeadsetSnapshot) -> DiagnosticReport {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let appVersion = [version, build].compactMap { $0 }.joined(separator: " (")

        return DiagnosticReport(
            formatVersion: 1,
            generatedAt: .now,
            appVersion: appVersion.isEmpty ? "development" : appVersion + (build == nil ? "" : ")"),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            privacy: "Personal diagnostic build: headset and receiver identifiers are retained for interface correlation.",
            device: DiagnosticReport.Device(
                model: snapshot.device.model,
                headsetFirmware: snapshot.device.headsetFirmware,
                receiverFirmware: snapshot.device.receiverFirmware,
                batteryPercent: snapshot.device.batteryPercent,
                transport: snapshot.device.transport?.rawValue
            ),
            capabilities: CapabilityCatalog.all.map {
                DiagnosticReport.Capability(
                    key: $0.key.rawValue,
                    qualification: $0.qualification.rawValue,
                    recipe: $0.recipe.summary,
                    evidence: $0.evidence
                )
            },
            entries: entries
        )

    }

    public static func hex(_ data: Data, limit: Int = 8_192) -> String {
        let prefix = data.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return data.count > limit ? prefix + " … (\(data.count) bytes total)" : prefix
    }
}

public enum DiagnosticExporter {
    @concurrent
    public static func encode(_ report: DiagnosticReport) async throws -> Data {
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try Task.checkCancellation()
        return data
    }

    @concurrent
    public static func write(_ data: Data, to url: URL) async throws {
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
        try Task.checkCancellation()
    }
}
