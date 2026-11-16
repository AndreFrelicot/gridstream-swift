//
//  Logger.swift
//  gridstream-ipad
//

import OSLog

enum AppLogger {
    nonisolated private static let subsystem = "com.gridstream.ipad"

    nonisolated static let grid = Logger(subsystem: subsystem, category: "Grid")
    nonisolated static let overlay = Logger(subsystem: subsystem, category: "Overlay")
    nonisolated static let discovery = Logger(subsystem: subsystem, category: "Discovery")
    nonisolated static let video = Logger(subsystem: subsystem, category: "Video")
    nonisolated static let playback = Logger(subsystem: subsystem, category: "Playback")
    nonisolated static let session = Logger(subsystem: subsystem, category: "Session")
    nonisolated static let pip = Logger(subsystem: subsystem, category: "PiP")
}
