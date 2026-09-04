@preconcurrency import IOKit.hid
import Foundation

struct HIDInterfaceIdentity: Hashable, Sendable, CustomStringConvertible {
    let registryEntryID: UInt64?
    let locationID: Int
    let usagePage: Int
    let usage: Int
    let sessionIdentifier: String

    var description: String {
        if let registryEntryID { return "registry:\(registryEntryID)" }
        return "fallback:\(locationID):\(usagePage):\(usage):\(sessionIdentifier)"
    }

    func hash(into hasher: inout Hasher) {
        if let registryEntryID {
            hasher.combine(0)
            hasher.combine(registryEntryID)
        } else {
            hasher.combine(1)
            hasher.combine(locationID)
            hasher.combine(usagePage)
            hasher.combine(usage)
            hasher.combine(sessionIdentifier)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.registryEntryID, rhs.registryEntryID) {
        case (.some(let lhsID), .some(let rhsID)): lhsID == rhsID
        case (nil, nil):
            lhs.locationID == rhs.locationID
                && lhs.usagePage == rhs.usagePage
                && lhs.usage == rhs.usage
                && lhs.sessionIdentifier == rhs.sessionIdentifier
        default: false
        }
    }
}

struct HIDInterfaceDescriptor: Sendable, Equatable {
    let identity: HIDInterfaceIdentity
    let summary: HIDDeviceSummary
    let diagnosticDetails: [String: String]
}

struct HIDInputEvent: Sendable, Equatable {
    let identity: HIDInterfaceIdentity
    let usagePage: Int
    let usage: Int
    let reportID: Int
    let value: Int
    let timestamp: UInt64
}

enum HIDSourceEvent: Sendable, Equatable {
    case matched(HIDInterfaceDescriptor)
    case removed(HIDInterfaceIdentity)
    case input(HIDInputEvent)
}

@MainActor
protocol HIDEventSourcing: AnyObject {
    func start(eventHandler: @escaping @Sendable (HIDSourceEvent) -> Void) -> IOReturn
    func stop()
}

@MainActor
protocol HIDMonitoring: AnyObject {
    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void)
    func stop()
}

@MainActor
final class HIDMonitor: HIDMonitoring {
    private let source: any HIDEventSourcing
    private let recorder: DiagnosticRecorder
    private var interfaces: [HIDInterfaceIdentity: HIDInterfaceDescriptor] = [:]
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?

    var retainedInterfaceCount: Int { interfaces.count }

    init(
        source: any HIDEventSourcing = IOHIDEventSource(),
        recorder: DiagnosticRecorder = .shared
    ) {
        self.source = source
        self.recorder = recorder
    }

    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler
        let result = source.start { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
        guard result == kIOReturnSuccess else {
            let code = String(format: "0x%08X", UInt32(bitPattern: result))
            recorder.record(
                "hid",
                "Unable to open the HID manager",
                details: ["ioReturn": code]
            )
            source.stop()
            updateHandler(.failed(
                source: .receiver,
                message: "Unable to open the USB receiver monitor (\(code)).",
                willRetry: false
            ))
            return
        }
        updateHandler(.searching(.receiver))
    }

    func stop() {
        source.stop()
        interfaces.removeAll(keepingCapacity: true)
        updateHandler = nil
    }

    private func handle(_ event: HIDSourceEvent) {
        switch event {
        case .matched(let descriptor):
            guard Self.isWL5024Candidate(descriptor.summary), interfaces[descriptor.identity] == nil else {
                return
            }
            interfaces[descriptor.identity] = descriptor
            recorder.record(
                "hid",
                "WL5024 receiver interface matched",
                details: descriptor.diagnosticDetails
            )
            updateHandler?(.receiverFound(descriptor.summary))

        case .removed(let identity):
            guard interfaces.removeValue(forKey: identity) != nil else { return }
            recorder.record(
                "hid",
                "WL5024 receiver interface removed",
                details: ["interfaceIdentity": identity.description]
            )
            if interfaces.isEmpty {
                updateHandler?(.receiverRemoved)
            }

        case .input(let input):
            guard interfaces[input.identity] != nil else { return }
            recorder.record(
                "hid-input",
                "Input value",
                details: [
                    "interfaceIdentity": input.identity.description,
                    "usagePage": String(input.usagePage),
                    "usage": String(input.usage),
                    "reportID": String(input.reportID),
                    "value": String(input.value),
                    "timestamp": String(input.timestamp),
                ]
            )
        }
    }

    static func isWL5024Candidate(_ summary: HIDDeviceSummary) -> Bool {
        let identity = "\(summary.manufacturer) \(summary.product)".lowercased()
        let namedCandidate = ["wl5024", "hr024", "ud2403", "pegasus"].contains {
            identity.contains($0)
        }
        let dellIdentity = summary.vendorID == 0x413C && namedCandidate
        let updaterIdentity = summary.vendorID == 0x0E8D && summary.productID == 0x0808
        return dellIdentity || updaterIdentity
    }
}

@MainActor
private final class IOHIDEventSource: HIDEventSourcing {
    private let manager: IOHIDManager
    private var eventHandler: (@Sendable (HIDSourceEvent) -> Void)?
    private var isScheduled = false

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start(eventHandler: @escaping @Sendable (HIDSourceEvent) -> Void) -> IOReturn {
        self.eventHandler = eventHandler
        let matching: [[String: Int]] = [
            [kIOHIDVendorIDKey: 0x413C],
            [kIOHIDVendorIDKey: 0x0E8D, kIOHIDProductIDKey: 0x0808],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            RunLoop.main.getCFRunLoop(),
            CFRunLoopMode.defaultMode.rawValue
        )
        isScheduled = true
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            stop()
        }
        return result
    }

    func stop() {
        if isScheduled {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                RunLoop.main.getCFRunLoop(),
                CFRunLoopMode.defaultMode.rawValue
            )
            isScheduled = false
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        eventHandler = nil
    }

    private func matched(_ device: IOHIDDevice) {
        eventHandler?(.matched(Self.descriptor(for: device)))
    }

    private func removed(_ device: IOHIDDevice) {
        eventHandler?(.removed(Self.identity(for: device)))
    }

    private func input(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        eventHandler?(.input(HIDInputEvent(
            identity: Self.identity(for: device),
            usagePage: Int(IOHIDElementGetUsagePage(element)),
            usage: Int(IOHIDElementGetUsage(element)),
            reportID: Int(IOHIDElementGetReportID(element)),
            value: IOHIDValueGetIntegerValue(value),
            timestamp: IOHIDValueGetTimeStamp(value)
        )))
    }

    private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let address = UInt(bitPattern: context)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
            Unmanaged<IOHIDEventSource>.fromOpaque(pointer).takeUnretainedValue().matched(device)
        }
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let address = UInt(bitPattern: context)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
            Unmanaged<IOHIDEventSource>.fromOpaque(pointer).takeUnretainedValue().removed(device)
        }
    }

    private static let inputCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let address = UInt(bitPattern: context)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
            Unmanaged<IOHIDEventSource>.fromOpaque(pointer).takeUnretainedValue().input(value)
        }
    }

    private static func descriptor(for device: IOHIDDevice) -> HIDInterfaceDescriptor {
        let summary = HIDDeviceSummary(
            vendorID: integerProperty(kIOHIDVendorIDKey as CFString, device: device),
            productID: integerProperty(kIOHIDProductIDKey as CFString, device: device),
            manufacturer: stringProperty(kIOHIDManufacturerKey as CFString, device: device),
            product: stringProperty(kIOHIDProductKey as CFString, device: device),
            serialNumber: stringProperty(kIOHIDSerialNumberKey as CFString, device: device),
            maximumInputReportSize: integerProperty(kIOHIDMaxInputReportSizeKey as CFString, device: device),
            maximumOutputReportSize: integerProperty(kIOHIDMaxOutputReportSizeKey as CFString, device: device)
        )
        let identity = identity(for: device)
        var details = summary.diagnosticDetails
        if let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
            details["reportDescriptor"] = DiagnosticRecorder.hex(descriptor)
        }
        details["interfaceIdentity"] = identity.description
        details["primaryUsagePage"] = String(identity.usagePage)
        details["primaryUsage"] = String(identity.usage)
        details["transport"] = stringProperty(kIOHIDTransportKey as CFString, device: device)
        details["locationID"] = String(identity.locationID)
        return HIDInterfaceDescriptor(identity: identity, summary: summary, diagnosticDetails: details)
    }

    private static func identity(for device: IOHIDDevice) -> HIDInterfaceIdentity {
        var registryEntryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        let registryResult = IORegistryEntryGetRegistryEntryID(service, &registryEntryID)
        let uniqueID = stringProperty("UniqueID" as CFString, device: device)
        let serial = stringProperty(kIOHIDSerialNumberKey as CFString, device: device)
        let pointer = String(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
        return HIDInterfaceIdentity(
            registryEntryID: registryResult == KERN_SUCCESS ? registryEntryID : nil,
            locationID: integerProperty(kIOHIDLocationIDKey as CFString, device: device),
            usagePage: integerProperty(kIOHIDPrimaryUsagePageKey as CFString, device: device),
            usage: integerProperty(kIOHIDPrimaryUsageKey as CFString, device: device),
            sessionIdentifier: uniqueID.isEmpty ? (serial.isEmpty ? pointer : serial) : uniqueID
        )
    }

    private static func integerProperty(_ key: CFString, device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue ?? 0
    }

    private static func stringProperty(_ key: CFString, device: IOHIDDevice) -> String {
        IOHIDDeviceGetProperty(device, key) as? String ?? ""
    }
}
