//
//  Tile.swift
//  gridstream-ipad
//

import Foundation

struct Tile: Identifiable, Equatable {
    let id: UUID
    let index: Int
    var videoURL: URL?
    var videoId: String?
    var playCount: Int = 0
    var totalViewTime: Int = 0
    var smartListId: UUID?
    var simpleListId: UUID?

    var hasVideo: Bool {
        videoURL != nil
    }

    init(
        index: Int,
        id: UUID = UUID(),
        videoURL: URL? = nil,
        videoId: String? = nil,
        playCount: Int = 0,
        totalViewTime: Int = 0,
        smartListId: UUID? = nil,
        simpleListId: UUID? = nil
    ) {
        self.id = id
        self.index = index
        self.videoURL = videoURL
        self.videoId = videoId
        self.playCount = playCount
        self.totalViewTime = totalViewTime
        self.smartListId = smartListId
        self.simpleListId = simpleListId
    }
}
