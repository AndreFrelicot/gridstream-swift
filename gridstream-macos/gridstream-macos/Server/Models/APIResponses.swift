import Foundation
import GridStreamAPI
import Vapor

nonisolated struct VideosResponse: Content {
    let videos: [VideoItem]
}

nonisolated struct HealthResponse: Content {
    let status: String
    let version: String
}
