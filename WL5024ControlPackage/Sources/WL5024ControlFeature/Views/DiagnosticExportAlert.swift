import Foundation

enum DiagnosticExportAlert: Identifiable {
    case saved(filename: String, byteCount: Int)
    case failed

    var id: String {
        switch self {
        case .saved(let filename, _): "saved.\(filename)"
        case .failed: "failed"
        }
    }
}
