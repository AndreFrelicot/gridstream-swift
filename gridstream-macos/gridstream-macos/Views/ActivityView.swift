//
//  ActivityView.swift
//  gridstream-macos
//
//  Settings > Activity: the devices using the server, what they are playing
//  and how fast, and the connection log.
//

import AppKit
import SwiftUI

struct ActivityView: View {
    var serverManager: ServerManager

    private var activity: ConnectionActivity { serverManager.activity }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 24) {
                    StatTile(title: "Devices", value: "\(activity.clients.count)", systemImage: "ipad.and.iphone")
                    StatTile(title: "Playing", value: "\(activity.streamCount)", systemImage: "play.rectangle")
                    StatTile(title: "Throughput", value: ActivityFormat.rate(activity.bytesPerSecond), systemImage: "speedometer")
                    StatTile(title: "Videos Served", value: "\(activity.videosServed)", systemImage: "film.stack")
                }
                .padding(.vertical, 4)
            } footer: {
                if serverManager.isRunning {
                    Text("\(ActivityFormat.bytes(activity.bytesSent)) sent since the server started.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Connected Devices") {
                if !serverManager.isRunning {
                    Label("The server is stopped.", systemImage: "stop.circle")
                        .foregroundStyle(.secondary)
                } else if activity.clients.isEmpty {
                    Label("No device is connected. Devices appear here when they use the server.", systemImage: "ipad.landscape")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activity.clients) { client in
                        ClientRow(client: client)
                    }
                }
            }

            Section {
                if activity.events.isEmpty {
                    Text("Nothing logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activity.events) { event in
                        EventRow(event: event)
                    }
                }
            } header: {
                HStack {
                    Text("Log")
                    Spacer()
                    Button("Copy") { copyLog() }
                    Button("Clear") { activity.clearLog() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(activity.events.isEmpty)
            } footer: {
                Text("The last \(ConnectionActivity.maxEvents) entries, newest first. The log is cleared when GridStream quits.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func copyLog() {
        let text = activity.events.reversed().map(\.logLine).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Rows

private struct ClientRow: View {
    let client: ConnectedClient

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BrandSymbol(systemImage: client.identity.systemImage, size: 30)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.identity.name)
                            .font(.headline)
                        Text("\(client.identity.place) · connected at \(client.connectedAt, format: .dateTime.hour().minute())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ActivityFormat.rate(client.bytesPerSecond))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                        Text("\(ActivityFormat.bytes(client.bytesSent)) sent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                ForEach(client.streams) { stream in
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(Brand.orange)
                        Text(stream.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(ActivityFormat.rate(stream.bytesPerSecond))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct EventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.date, format: .dateTime.hour().minute().second())
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Image(systemName: event.kind.systemImage)
                .foregroundStyle(event.kind.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.kind.message)
                if let client = event.client {
                    Text("\(client.name) · \(client.place)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Wording

enum ActivityFormat {
    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        String(localized: "\(bytes(Int64(bytesPerSecond)))/s")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(1, seconds.rounded()))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }
}

extension ClientIdentity {
    var name: String {
        switch kind {
        case .iPad: String(localized: "iPad")
        case .browser(let name?): name
        case .browser(nil): String(localized: "Web Browser")
        case .unknown: String(localized: "Device")
        }
    }

    /// Where it connects from: this Mac, or its network address.
    var place: String {
        isThisMac ? String(localized: "This Mac") : address
    }

    var systemImage: String {
        switch kind {
        case .iPad: "ipad.landscape"
        case .browser: isThisMac ? "laptopcomputer" : "globe"
        case .unknown: "desktopcomputer"
        }
    }
}

extension ActivityEvent.Kind {
    var message: String {
        switch self {
        case .serverStarted(let port):
            String(localized: "Server started on port \(String(port))")
        case .serverStopped:
            String(localized: "Server stopped")
        case .connected:
            String(localized: "Connected")
        case .wentIdle(let bytesSent):
            String(localized: "No longer active, \(ActivityFormat.bytes(bytesSent)) sent")
        case .signedIn:
            String(localized: "Signed in")
        case .wrongPIN:
            String(localized: "Wrong PIN")
        case .signInBlocked:
            String(localized: "Too many wrong PINs, sign-in paused")
        case .signedOut:
            String(localized: "Signed out")
        case .streamStarted(let filename):
            String(localized: "Playing “\(filename)”")
        case .streamEnded(let filename, let bytesSent, let duration):
            String(localized: "Stopped “\(filename)” after \(ActivityFormat.duration(duration)), \(ActivityFormat.bytes(bytesSent)) sent")
        }
    }

    var systemImage: String {
        switch self {
        case .serverStarted, .serverStopped: "power"
        case .connected: "link"
        case .wentIdle: "moon.zzz"
        case .signedIn: "lock.open.fill"
        case .wrongPIN: "exclamationmark.lock.fill"
        case .signInBlocked: "hand.raised.fill"
        case .signedOut: "rectangle.portrait.and.arrow.right"
        case .streamStarted: "play.fill"
        case .streamEnded: "stop.fill"
        }
    }

    var tint: Color {
        switch self {
        case .serverStarted, .connected, .signedIn: .green
        case .wrongPIN, .signInBlocked: .red
        case .streamStarted: Brand.orange
        case .serverStopped, .wentIdle, .signedOut, .streamEnded: .secondary
        }
    }
}

extension ActivityEvent {
    /// One line of the copied log.
    var logLine: String {
        let time = date.formatted(.dateTime.year().month().day().hour().minute().second())
        guard let client else { return "\(time)  \(kind.message)" }
        return "\(time)  \(client.name) (\(client.place))  \(kind.message)"
    }
}
