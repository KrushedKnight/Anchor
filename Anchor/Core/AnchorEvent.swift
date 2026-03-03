import Foundation

struct AnchorEvent: Codable, Identifiable {
    let id: Int64
    let ts: Double
    let type: String
    let data: [String: String]
}
