@preconcurrency import IOKit.hid
import CoreFoundation
import Foundation
import WL5024ControlFeature

/// A single-request, read-only probe for the WL5024's directly attached USB HID channel.
///
/// The 0x06/0x07 report framing is recovered from Dell's AirohaHidCoreLib and is also
/// described by the physical device's report descriptor. Only the established generic
/// preference getter can be constructed here; setters, FOTA, and maintenance traffic are absent.
enum DirectUSBProbe {
    @discardableResult
    static func run(arguments: [String]) -> Int32 {
        let module = arguments.first(where: { $0.hasPrefix("--module=") })
            .flatMap { UInt16($0.dropFirst("--module=".count)) }
            ?? 0x0031
        let runner = Runner(module: module)
        guard runner.start() else { return runner.exitCode }
        withExtendedLifetime(runner) {
            CFRunLoopRun()
        }
        return runner.exitCode
    }
}

private extension DirectUSBProbe {
    // IOHID and timer callbacks are all scheduled on this process's main run loop.
    final class Runner: @unchecked Sendable {
        private static let vendorID = 0x413C
        private static let productID = 0xA520
        private static let outputReportID: UInt8 = 0x06
        private static let inputReportID: UInt8 = 0x07
        private static let reportLength = 62

        private let module: UInt16
        private let manager: IOHIDManager
        private let inputBuffer: UnsafeMutablePointer<UInt8>
        private let transaction: TransportTransaction
        private var device: IOHIDDevice?
        private var sendTimer: Timer?
        private var readTimer: Timer?
        private var timeoutTimer: Timer?
        private var lastReadError: IOReturn?
        private var finished = false
        private(set) var exitCode: Int32 = ProbeExitStatus.success

        init(module: UInt16) {
            self.module = module
            manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            inputBuffer = .allocate(capacity: Self.reportLength)
            inputBuffer.initialize(repeating: 0, count: Self.reportLength)
            transaction = WL5024Command.getPreference(module: module).transaction
        }

        deinit {
            inputBuffer.deinitialize(count: Self.reportLength)
            inputBuffer.deallocate()
        }

        func start() -> Bool {
            let matching: [String: Int] = [
                kIOHIDVendorIDKey: Self.vendorID,
                kIOHIDProductIDKey: Self.productID,
                kIOHIDPrimaryUsagePageKey: 0xFF13,
                kIOHIDPrimaryUsageKey: 1,
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
            IOHIDManagerScheduleWithRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                log("ERROR", "unable to open HID manager: \(ioResult(result))")
                IOHIDManagerUnscheduleFromRunLoop(
                    manager,
                    CFRunLoopGetMain(),
                    CFRunLoopMode.defaultMode.rawValue
                )
                exitCode = ProbeExitStatus.failure
                return false
            }

            log(
                "START",
                "read-only USB HID getter; device 413C:A520; preference module \(module)"
            )
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                self?.finish(status: "TIMEOUT", message: "no matching report 07 response within 5s")
            }
            return true
        }

        private func matched(_ matchedDevice: IOHIDDevice) {
            guard device == nil, !finished else { return }
            device = matchedDevice
            IOHIDDeviceRegisterInputReportCallback(
                matchedDevice,
                inputBuffer,
                Self.reportLength,
                Self.inputCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )

            let product = property(kIOHIDProductKey as CFString, device: matchedDevice) as? String
                ?? "unknown"
            let transport = property(kIOHIDTransportKey as CFString, device: matchedDevice) as? String
                ?? "unknown"
            log("MATCH", "\(product); transport=\(transport); reports 06 out / 07 in")
            sendTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.sendGetter()
            }
        }

        private func sendGetter() {
            guard let device, !finished else { return }
            let race = transaction.request
            guard race.count >= 2, race.count <= 59, race.first == RaceFrame.header else {
                finish(status: "ERROR", message: "getter failed the USB framing safety gate")
                return
            }

            var report = [UInt8](repeating: 0, count: Self.reportLength)
            report[0] = Self.outputReportID
            report[1] = UInt8(race.count)
            report[2] = 0x00 // Dell's local/non-GATT transport channel.
            report.replaceSubrange(3..<(race.count + 3), with: race)

            log("TX", hex(Data(report.prefix(race.count + 3))))
            let result = report.withUnsafeBytes { bytes in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(Self.outputReportID),
                    bytes.bindMemory(to: UInt8.self).baseAddress!,
                    Self.reportLength
                )
            }
            guard result == kIOReturnSuccess else {
                finish(status: "ERROR", message: "report 06 write failed: \(ioResult(result))")
                return
            }
            log("SENT", "62-byte report accepted by IOHID")
            readTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.pollInputReport()
            }
        }

        private func pollInputReport() {
            guard let device, !finished else { return }
            for index in 0..<Self.reportLength {
                inputBuffer[index] = 0
            }
            inputBuffer[0] = Self.inputReportID
            var length = Self.reportLength
            let result = IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeInput,
                CFIndex(Self.inputReportID),
                inputBuffer,
                &length
            )
            guard result == kIOReturnSuccess else {
                if lastReadError != result {
                    lastReadError = result
                    log("READ", "report 07 not ready: \(ioResult(result))")
                }
                return
            }
            received(
                result: result,
                reportType: kIOHIDReportTypeInput,
                reportID: UInt32(Self.inputReportID),
                report: inputBuffer,
                reportLength: length
            )
        }

        private func received(
            result: IOReturn,
            reportType: IOHIDReportType,
            reportID: UInt32,
            report: UnsafeMutablePointer<UInt8>,
            reportLength: CFIndex
        ) {
            guard !finished else { return }
            guard result == kIOReturnSuccess else {
                log("RX-ERROR", ioResult(result))
                return
            }
            guard reportType == kIOHIDReportTypeInput else { return }

            let count = max(0, min(Int(reportLength), Self.reportLength))
            let bytes = Data(bytes: report, count: count)
            guard reportID == Self.inputReportID,
                  let race = Self.unwrapInputReport(bytes, callbackReportID: UInt8(reportID)) else {
                return
            }
            log("RX", "id=\(reportID) length=\(count) | \(hex(bytes))")
            guard transaction.expectedResponse.matches(race),
                  let frame = try? RaceFrame(decoding: race) else {
                log("IGNORE", "report 07 did not match opcode/module for the pending getter")
                return
            }

            finish(
                status: "DONE",
                message: "USB getter matched module \(module): opcode=0x\(String(format: "%04X", frame.opcode)) "
                    + "payload=[\(hex(frame.payload))]"
            )
        }

        /// Accept both documented IOHID callback layouts: report ID present in the buffer or
        /// supplied only through the callback argument. Dell's wrapper is
        /// [07, continuation length, transport channel, continuation bytes].
        private static func unwrapInputReport(_ data: Data, callbackReportID: UInt8) -> Data? {
            let bytes = Array(data)
            let lengthIndex: Int
            let transportTypeIndex: Int
            if bytes.first == inputReportID {
                lengthIndex = 1
                transportTypeIndex = 2
            } else if callbackReportID == inputReportID {
                lengthIndex = 0
                transportTypeIndex = 1
            } else {
                return nil
            }
            guard bytes.indices.contains(transportTypeIndex), bytes.indices.contains(lengthIndex) else {
                return nil
            }
            let continuationLength = Int(bytes[lengthIndex])
            let end = transportTypeIndex + 1 + continuationLength
            guard continuationLength > 0, end <= bytes.count else { return nil }
            return Data(bytes[transportTypeIndex..<end])
        }

        private func finish(status: String, message: String) {
            guard !finished else { return }
            finished = true
            exitCode = status == "DONE" ? ProbeExitStatus.success : ProbeExitStatus.failure
            sendTimer?.invalidate()
            readTimer?.invalidate()
            timeoutTimer?.invalidate()
            log(status, message)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            CFRunLoopStop(CFRunLoopGetMain())
        }

        private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
            guard let context else { return }
            Unmanaged<Runner>.fromOpaque(context).takeUnretainedValue().matched(device)
        }

        private static let inputCallback: IOHIDReportCallback = {
            context,
            result,
            _,
            reportType,
            reportID,
            report,
            reportLength in
            guard let context else { return }
            Unmanaged<Runner>.fromOpaque(context).takeUnretainedValue().received(
                result: result,
                reportType: reportType,
                reportID: reportID,
                report: report,
                reportLength: reportLength
            )
        }

        private func property(_ key: CFString, device: IOHIDDevice) -> Any? {
            IOHIDDeviceGetProperty(device, key)
        }

        private func ioResult(_ result: IOReturn) -> String {
            String(format: "0x%08X", UInt32(bitPattern: result))
        }

        private func hex(_ data: Data) -> String {
            data.map { String(format: "%02X", $0) }.joined(separator: " ")
        }

        private func log(_ status: String, _ message: String) {
            print("[USB \(status)] \(message)")
            fflush(stdout)
        }
    }
}
