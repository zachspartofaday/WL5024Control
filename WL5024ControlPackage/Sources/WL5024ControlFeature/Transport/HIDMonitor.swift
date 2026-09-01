@preconcurrency import IOKit.hid
import Foundation

@MainActor
final class HIDMonitor {
    private let manager: IOHIDManager
    private var matchedDevice: IOHIDDevice?
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler

        IOHIDManagerSetDeviceMatching(manager, nil)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.handleMatched(device)
                }
            },
            context
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.handleRemoved(device)
                }
            },
            context
        )
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, _, _, value in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.handleInput(value)
                }
            },
            context
        )
        IOHIDManagerScheduleWithRunLoop(
            manager,
            RunLoop.main.getCFRunLoop(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            RunLoop.main.getCFRunLoop(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        matchedDevice = nil
        updateHandler = nil
    }

    private func handleMatched(_ device: IOHIDDevice) {
        let summary = Self.summary(for: device)
        guard Self.isWL5024Candidate(summary) else { return }
        matchedDevice = device
        var details = summary.diagnosticDetails
        if let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
            details["reportDescriptor"] = DiagnosticRecorder.hex(descriptor)
        }
        details["primaryUsagePage"] = String(Self.integerProperty(kIOHIDPrimaryUsagePageKey as CFString, device: device))
        details["primaryUsage"] = String(Self.integerProperty(kIOHIDPrimaryUsageKey as CFString, device: device))
        details["transport"] = Self.stringProperty(kIOHIDTransportKey as CFString, device: device)
        details["locationID"] = String(Self.integerProperty(kIOHIDLocationIDKey as CFString, device: device))
        DiagnosticRecorder.shared.record("hid", "WL5024 receiver interface matched", details: details)
        updateHandler?(.receiverFound(summary))
    }

    private func handleRemoved(_ device: IOHIDDevice) {
        guard let matchedDevice, CFEqual(matchedDevice, device) else { return }
        self.matchedDevice = nil
        DiagnosticRecorder.shared.record("hid", "WL5024 receiver interface removed")
        updateHandler?(.disconnected)
    }

    private func handleInput(_ value: IOHIDValue) {
        guard let matchedDevice else { return }
        let element = IOHIDValueGetElement(value)
        let elementDevice = IOHIDElementGetDevice(element)
        guard CFEqual(matchedDevice, elementDevice) else {
            return
        }

        DiagnosticRecorder.shared.record(
            "hid-input",
            "Input value",
            details: [
                "usagePage": String(IOHIDElementGetUsagePage(element)),
                "usage": String(IOHIDElementGetUsage(element)),
                "reportID": String(IOHIDElementGetReportID(element)),
                "value": String(IOHIDValueGetIntegerValue(value)),
                "timestamp": String(IOHIDValueGetTimeStamp(value)),
            ]
        )
    }

    static func summary(for device: IOHIDDevice) -> HIDDeviceSummary {
        HIDDeviceSummary(
            vendorID: integerProperty(kIOHIDVendorIDKey as CFString, device: device),
            productID: integerProperty(kIOHIDProductIDKey as CFString, device: device),
            manufacturer: stringProperty(kIOHIDManufacturerKey as CFString, device: device),
            product: stringProperty(kIOHIDProductKey as CFString, device: device),
            serialNumber: stringProperty(kIOHIDSerialNumberKey as CFString, device: device),
            maximumInputReportSize: integerProperty(kIOHIDMaxInputReportSizeKey as CFString, device: device),
            maximumOutputReportSize: integerProperty(kIOHIDMaxOutputReportSizeKey as CFString, device: device)
        )
    }

    private static func isWL5024Candidate(_ summary: HIDDeviceSummary) -> Bool {
        let identity = "\(summary.manufacturer) \(summary.product)".lowercased()
        let namedCandidate = ["wl5024", "hr024", "ud2403", "pegasus"].contains {
            identity.contains($0)
        }
        let updaterIdentity = summary.vendorID == 0x0E8D && summary.productID == 0x0808
        return namedCandidate || updaterIdentity
    }

    private static func integerProperty(_ key: CFString, device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue ?? 0
    }

    private static func stringProperty(_ key: CFString, device: IOHIDDevice) -> String {
        IOHIDDeviceGetProperty(device, key) as? String ?? ""
    }
}
