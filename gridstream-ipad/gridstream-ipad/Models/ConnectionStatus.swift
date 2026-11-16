//
//  ConnectionStatus.swift
//  gridstream-ipad
//

import Foundation

enum ConnectionStatus: Equatable {
    case searching
    case found(serverName: String)
    case connected
    case disconnected

    var displayText: LocalizedStringResource {
        switch self {
        case .searching:
            return "Searching..."
        case .found(let serverName):
            return "Found: \(serverName)"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        }
    }
}
