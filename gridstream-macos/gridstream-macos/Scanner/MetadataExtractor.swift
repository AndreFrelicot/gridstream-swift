import AVFoundation
import Foundation
import OSLog

nonisolated struct VideoMetadata {
    let duration: Double
    let width: Int
    let height: Int
    let codec: String
    let fileSize: Int64
    let lastModified: Date
}

actor MetadataExtractor {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "MetadataExtractor")

    func extract(from url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)

        let duration = try await loadDuration(from: asset)
        let (width, height, codec) = try await loadVideoTrackInfo(from: asset)
        let (fileSize, lastModified) = try loadFileAttributes(from: url)

        return VideoMetadata(
            duration: duration,
            width: width,
            height: height,
            codec: codec,
            fileSize: fileSize,
            lastModified: lastModified
        )
    }

    private func loadDuration(from asset: AVURLAsset) async throws -> Double {
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private func loadVideoTrackInfo(from asset: AVURLAsset) async throws -> (width: Int, height: Int, codec: String) {
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = tracks.first else {
            logger.warning("No video track found in asset")
            return (width: 0, height: 0, codec: "unknown")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let width = Int(naturalSize.width)
        let height = Int(naturalSize.height)

        let codec = try await extractCodec(from: videoTrack)

        return (width: width, height: height, codec: codec)
    }

    private func extractCodec(from track: AVAssetTrack) async throws -> String {
        let formatDescriptions = try await track.load(.formatDescriptions)

        guard let formatDescription = formatDescriptions.first else {
            return "unknown"
        }

        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
        return codecName(from: mediaSubType)
    }

    private func codecName(from fourCC: FourCharCode) -> String {
        switch fourCC {
        case kCMVideoCodecType_H264:
            return "h264"
        case kCMVideoCodecType_HEVC:
            return "hevc"
        case kCMVideoCodecType_MPEG4Video:
            return "mpeg4"
        case kCMVideoCodecType_AppleProRes422:
            return "prores422"
        case kCMVideoCodecType_AppleProRes4444:
            return "prores4444"
        case kCMVideoCodecType_AppleProRes422HQ:
            return "prores422hq"
        case kCMVideoCodecType_AppleProRes422LT:
            return "prores422lt"
        case kCMVideoCodecType_AppleProRes422Proxy:
            return "prores422proxy"
        default:
            let chars = [
                Character(UnicodeScalar((fourCC >> 24) & 0xFF)!),
                Character(UnicodeScalar((fourCC >> 16) & 0xFF)!),
                Character(UnicodeScalar((fourCC >> 8) & 0xFF)!),
                Character(UnicodeScalar(fourCC & 0xFF)!)
            ]
            return String(chars).trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    private func loadFileAttributes(from url: URL) throws -> (fileSize: Int64, lastModified: Date) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        let fileSize = (attributes[.size] as? Int64) ?? 0
        let lastModified = (attributes[.modificationDate] as? Date) ?? Date()

        return (fileSize: fileSize, lastModified: lastModified)
    }
}
