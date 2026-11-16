//
//  WebUISettingsView.swift
//  gridstream-macos
//
//  Settings tab for the browser UI the server hosts on its own port.
//

import AppKit
import SwiftUI

struct WebUISettingsView: View {
    var serverManager: ServerManager
    @Bindable var configurationService: ConfigurationService
    var onStartServer: () -> Void

    var body: some View {
        Form {
            Section {
                if ServerManager.isWebUIBundled {
                    Toggle("Serve the web interface", isOn: $configurationService.webUIEnabled)
                } else {
                    Label(
                        "This build of GridStream does not include the web interface. Install Node.js and rebuild the app, or run scripts/build-web.sh before building.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Web Interface")
            } footer: {
                Text("Browse and manage your library from any browser on your network. The web interface is served on the same port as the API used by the iPad.")
                    .foregroundStyle(.secondary)
            }

            if ServerManager.isWebUIBundled && configurationService.webUIEnabled {
                addressSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var addressSection: some View {
        Section {
            LabeledContent("Address") {
                HStack(spacing: 6) {
                    Text(webUIURL.absoluteString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    CopyButton(text: webUIURL.absoluteString)
                }
            }

            HStack {
                if serverManager.isRunning {
                    Spacer()
                    Button("Open in Browser") {
                        NSWorkspace.shared.open(webUIURL)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("The server is stopped.", systemImage: "circle.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Start Server") {
                        onStartServer()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var webUIURL: URL {
        Brand.localNetworkURL(port: serverManager.currentPort ?? configurationService.serverPort)
    }
}
