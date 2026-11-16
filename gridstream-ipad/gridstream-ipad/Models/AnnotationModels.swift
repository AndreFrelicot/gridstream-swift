import Foundation

struct StrokeData: Codable, Sendable {
    let color: String      // hex e.g. "#FF0000"
    let width: Double
    let opacity: Double
    let points: [StrokePoint]
}

struct StrokePoint: Codable, Sendable {
    let x: Double          // 0.0-1.0 normalized to video dimensions
    let y: Double
    let pressure: Double   // 0.0-1.0
}
