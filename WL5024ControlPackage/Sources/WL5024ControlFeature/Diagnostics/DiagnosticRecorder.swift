import Foundation

public struct DiagnosticEntry: Codable, Identifiable, Sendable {
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

public struct DiagnosticReport: Codable, Sendable {
    public struct Device: Codable, Sendable {
        public let model: String
        public let headsetFirmware: String?
        public let receiverFirmware: String?
        public let batteryPercent: Int?
        public let transport: String?
    }

    public struct Capability: Codable, Sendable {
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
}

@MainActor
public final class DiagnosticRecorder {
    public static let shared = DiagnosticRecorder()

    public private(set) var entries: [DiagnosticEntry] = []
    private let maximumEntries = 5_000

    private init() {}

    public func record(
        _ category: String,
        _ message: String,
        details: [String: String] = [:]
    ) {
        entries.append(DiagnosticEntry(category: category, message: message, details: details))
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
    }

    public func encodedReport(snapshot: HeadsetSnapshot) throws -> Data {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let appVersion = [version, build].compactMap { $0 }.joined(separator: " (")

        let report = DiagnosticReport(
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

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    public static func hex(_ data: Data, limit: Int = 8_192) -> String {
        let prefix = data.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return data.count > limit ? prefix + " … (\(data.count) bytes total)" : prefix
    }
}
