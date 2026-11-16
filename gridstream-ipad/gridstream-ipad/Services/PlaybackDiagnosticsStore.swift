//
//  PlaybackDiagnosticsStore.swift
//  gridstream-ipad
//

import Foundation
import OSLog

nonisolated struct PlaybackDiagnosticEvent: Codable, Identifiable, Sendable {
    enum Level: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    let id: UUID
    let timestamp: Date
    let uptime: TimeInterval
    let level: Level
    let name: String
    let message: String?
    let snapshot: PlaybackDiagnosticSnapshot

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        level: Level,
        name: String,
        message: String? = nil,
        snapshot: PlaybackDiagnosticSnapshot
    ) {
        self.id = id
        self.timestamp = timestamp
        self.uptime = uptime
        self.level = level
        self.name = name
        self.message = message
        self.snapshot = snapshot
    }

    var isIncident: Bool {
        level != .info || ["playback_stalled", "unexpected_pause", "playback_failed"].contains(name)
    }
}

nonisolated struct PlaybackDiagnosticSnapshot: Codable, Sendable {
    let playerID: String
    let videoFileID: String?
    let tileIndex: Int?
    let displayContext: String
    let playbackTime: Double
    let duration: Double
    let rate: Float
    let wantsToPlay: Bool
    let isPlaying: Bool
    let isSeeking: Bool
    let timeControlStatus: String
    let waitingReason: String?
    let playerStatus: String
    let itemStatus: String
    let bufferEmpty: Bool
    let likelyToKeepUp: Bool
    let bufferedAhead: Double
    let activePlayerCount: Int
    let videoWidth: Double
    let videoHeight: Double
    let frameRate: Float
    let thermalState: String
    let lowPowerModeEnabled: Bool
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
    let bytesTransferred: Int64?
    let transferDuration: Double?
    let observedBitrate: Double?
    let averageVideoBitrate: Double?
    let numberOfStalls: Int?
    let droppedVideoFrames: Int?
    let serverAddress: String?
}

nonisolated struct PlaybackDiagnosticsMetadata: Sendable {
    let eventCount: Int
    let fileSize: Int64
    let oldestEventDate: Date?
    let newestEventDate: Date?
}

actor PlaybackDiagnosticsStore {
    static let shared = PlaybackDiagnosticsStore()

    nonisolated static let maximumFileSize = 5 * 1024 * 1024
    nonisolated static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    private let directoryURL: URL
    private let logFileURL: URL
    private let maximumFileSize: Int
    private let maximumAge: TimeInterval
    private var recordsSincePrune = 0

    init(
        directoryURL: URL? = nil,
        maximumFileSize: Int = PlaybackDiagnosticsStore.maximumFileSize,
        maximumAge: TimeInterval = PlaybackDiagnosticsStore.maximumAge
    ) {
        let baseURL = directoryURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let diagnosticsDirectory = baseURL
            .appendingPathComponent("GridStream", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)

        self.directoryURL = diagnosticsDirectory
        self.logFileURL = diagnosticsDirectory.appendingPathComponent("playback-diagnostics.jsonl")
        self.maximumFileSize = maximumFileSize
        self.maximumAge = maximumAge
    }

    func record(_ event: PlaybackDiagnosticEvent) {
        do {
            try ensureDirectoryExists()
            recordsSincePrune += 1

            let currentSize = fileSize()
            if recordsSincePrune >= 50 || currentSize >= Int64(maximumFileSize) {
                try prune()
                recordsSincePrune = 0
            }

            var data = try Self.encoder.encode(event)
            data.append(0x0A)
            try append(data)
            if fileSize() > Int64(maximumFileSize) {
                try prune()
            }
        } catch {
            AppLogger.playback.error("Failed to persist playback diagnostic: \(error.localizedDescription)")
        }
    }

    func events() -> [PlaybackDiagnosticEvent] {
        do {
            try prune()
            return try readEvents().sorted {
                $0.timestamp == $1.timestamp ? $0.uptime > $1.uptime : $0.timestamp > $1.timestamp
            }
        } catch {
            AppLogger.playback.error("Failed to read playback diagnostics: \(error.localizedDescription)")
            return []
        }
    }

    func metadata() -> PlaybackDiagnosticsMetadata {
        let storedEvents = events()
        return PlaybackDiagnosticsMetadata(
            eventCount: storedEvents.count,
            fileSize: fileSize(),
            oldestEventDate: storedEvents.last?.timestamp,
            newestEventDate: storedEvents.first?.timestamp
        )
    }

    func exportText() -> String {
        guard let data = try? Data(contentsOf: logFileURL) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func exportURL() -> URL? {
        do {
            try ensureDirectoryExists()
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                try Data().write(to: logFileURL, options: .atomic)
            }
            return logFileURL
        } catch {
            AppLogger.playback.error("Failed to prepare playback diagnostic export: \(error.localizedDescription)")
            return nil
        }
    }

    func clear() {
        do {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                try FileManager.default.removeItem(at: logFileURL)
            }
            recordsSincePrune = 0
        } catch {
            AppLogger.playback.error("Failed to clear playback diagnostics: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func append(_ data: Data) throws {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try data.write(to: logFileURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: logFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func readEvents() throws -> [PlaybackDiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else { return [] }
        let data = try Data(contentsOf: logFileURL)

        return data.split(separator: 0x0A).compactMap { line in
            try? Self.decoder.decode(PlaybackDiagnosticEvent.self, from: Data(line))
        }
    }

    private func prune() throws {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

        let cutoffDate = Date().addingTimeInterval(-maximumAge)
        let recentEvents = try readEvents()
            .filter { $0.timestamp >= cutoffDate }
            .sorted {
                $0.timestamp == $1.timestamp ? $0.uptime < $1.uptime : $0.timestamp < $1.timestamp
            }

        var encodedLines = try recentEvents.map { event -> Data in
            var data = try Self.encoder.encode(event)
            data.append(0x0A)
            return data
        }

        var totalSize = encodedLines.reduce(0) { $0 + $1.count }
        while totalSize > maximumFileSize, !encodedLines.isEmpty {
            totalSize -= encodedLines.removeFirst().count
        }

        var prunedData = Data(capacity: totalSize)
        for line in encodedLines {
            prunedData.append(line)
        }
        try prunedData.write(to: logFileURL, options: .atomic)
    }

    private func fileSize() -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
