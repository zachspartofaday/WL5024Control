import Foundation

public struct HIDDeviceSummary: Sendable, Equatable, Codable {
    public let vendorID: Int
    public let productID: Int
    public let manufacturer: String
    public let product: String
    public let serialNumber: String
    public let maximumInputReportSize: Int
    public let maximumOutputReportSize: Int

    public init(
        vendorID: Int,
        productID: Int,
        manufacturer: String,
        product: String,
        serialNumber: String,
        maximumInputReportSize: Int,
        maximumOutputReportSize: Int
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.manufacturer = manufacturer
        self.product = product
        self.serialNumber = serialNumber
        self.maximumInputReportSize = maximumInputReportSize
        self.maximumOutputReportSize = maximumOutputReportSize
    }
}

extension HIDDeviceSummary {
    var diagnosticDetails: [String: String] {
        [
            "vendorID": String(format: "0x%04X", vendorID),
            "productID": String(format: "0x%04X", productID),
            "manufacturer": manufacturer,
            "product": product,
            "serialNumber": serialNumber,
            "maximumInputReportSize": String(maximumInputReportSize),
            "maximumOutputReportSize": String(maximumOutputReportSize),
        ]
    }
}
