//
//  Brand.swift
//  gridstream-macos
//
//  Shared look of the server windows: the amber-to-red gradient of the app
//  icon (the same one the iPad app uses), symbol tiles and the status badge.
//

import AppKit
import SwiftUI
import SystemConfiguration

enum Brand {
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let orange = Color(red: 0.92, green: 0.35, blue: 0.05)
    static let ember = Color(red: 0.70, green: 0.14, blue: 0.12)

    static let gradient = LinearGradient(
        colors: [amber, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// `http://<local host name>.local:<port>`, the Bonjour name other devices
    /// on the network can reach.
    static func localNetworkURL(port: Int) -> URL {
        let host = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" } ?? "localhost"
        return URL(string: "http://\(host):\(port)") ?? URL(string: "http://localhost:\(port)")!
    }
}

/// An SF Symbol, white on a rounded tile in the icon's gradient.
struct BrandSymbol: View {
    let systemImage: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The app icon, as shown in the Dock.
struct AppIconImage: View {
    var size: CGFloat = 48

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "Running" / "Stopped" capsule with a coloured dot.
struct ServerStatusBadge: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(isRunning ? "Running" : "Stopped")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((isRunning ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
        .foregroundStyle(isRunning ? Color.green : Color.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// A large figure with a caption, for the statistics rows.
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
