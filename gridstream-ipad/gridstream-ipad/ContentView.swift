//
//  ContentView.swift
//  gridstream-ipad
//
//  Created by Andre Frelicot on 18/12/2025.
//

import SwiftUI

struct ContentView: View {
    @Environment(ServerDiscoveryService.self) private var discoveryService
    @Environment(ServerSessionManager.self) private var sessionManager
    @Environment(DemoController.self) private var demoController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // One stable GridView: its state (and an open library sheet)
            // survives the server briefly disappearing and session checks.
            GridView()

            sessionOverlay
        }
        .fullScreenCover(item: coverFlow) { flow in
            switch flow {
            case .onboarding:
                OnboardingView()
            case .connectMac:
                ConnectMacView()
            case .demoDownload:
                DemoDownloadView()
            case .credits, .help:
                EmptyView()
            }
        }
        .sheet(item: sheetFlow) { flow in
            if flow == .help {
                HelpView()
            } else {
                DemoCreditsView()
            }
        }
        // Re-check the session when the active server changes or (re)appears
        // — e.g. a server that was off at launch and has no PIN unlocks
        // without user action.
        .task(id: sessionCheckKey) {
            await refreshSession()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active, oldPhase != .active else { return }
            Task {
                await refreshSession()
            }
        }
    }

    @ViewBuilder
    private var sessionOverlay: some View {
        if let server = discoveryService.activeServer,
           let serverURL = server.url {
            switch sessionManager.state {
            case .checking:
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            case .locked where sessionManager.authEnabled:
                PINLockView(
                    serverName: server.name,
                    errorMessage: sessionManager.errorMessage,
                    retryAfter: sessionManager.loginRetryAfter,
                    onSubmit: { pin in
                        _ = await sessionManager.login(pin: pin, serverURL: serverURL)
                    }
                )
            case .locked, .authenticated, .cachedAuthenticated:
                EmptyView()
            }
        }
    }

    /// The credits and the help open as sheets; every other flow covers
    /// the screen.
    private var coverFlow: Binding<DemoController.Flow?> {
        Binding(
            get: { isSheet(demoController.flow) ? nil : demoController.flow },
            set: { demoController.flow = $0 }
        )
    }

    private var sheetFlow: Binding<DemoController.Flow?> {
        Binding(
            get: { isSheet(demoController.flow) ? demoController.flow : nil },
            set: { demoController.flow = $0 }
        )
    }

    private func isSheet(_ flow: DemoController.Flow?) -> Bool {
        flow == .credits || flow == .help
    }

    private var sessionCheckKey: String {
        let identifier = discoveryService.targetServerIdentifier ?? ""
        let reachable = discoveryService.verifiedActiveServer != nil
        let present = discoveryService.activeServer != nil
        return "\(identifier)|\(present)|\(reachable)"
    }

    private func refreshSession() async {
        guard let serverURL = discoveryService.activeServerURL else { return }
        await sessionManager.refreshSession(for: serverURL)
    }
}

#Preview {
    let gridState = GridState()
    let discoveryService = ServerDiscoveryService()
    let sessionManager = ServerSessionManager.shared
    return ContentView()
        .environment(gridState)
        .environment(discoveryService)
        .environment(sessionManager)
        .environment(DemoController())
}
