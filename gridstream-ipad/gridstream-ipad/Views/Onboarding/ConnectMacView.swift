//
//  ConnectMacView.swift
//  gridstream-ipad
//
//  "Connect my Mac": explains the Local Network prompt before iPadOS shows
//  it, then follows the connection as a checklist (network, server, PIN).
//  After a while without a server it gives tips, the download link and
//  the demo as a way out.
//

import SwiftUI

struct ConnectMacView: View {
    @Environment(DemoController.self) private var demoController
    @Environment(ServerDiscoveryService.self) private var discoveryService
    @Environment(ServerSessionManager.self) private var sessionManager
    @Environment(GridState.self) private var gridState

    @State private var showsTips = false
    @State private var showsGetServer = false

    /// How long to look before suggesting what to check.
    private let tipsDelay: Duration = .seconds(10)

    private var server: DiscoveredServer? {
        guard let server = discoveryService.verifiedActiveServer, !DemoMode.isDemo(server) else { return nil }
        return server
    }

    private var isUnlocked: Bool {
        switch sessionManager.state {
        case .authenticated, .cachedAuthenticated:
            return true
        case .locked:
            return !sessionManager.authEnabled
        case .checking:
            return false
        }
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            ScrollView {
                OnboardingCard(maxWidth: 560) {
                    if demoController.allowsBrowsing {
                        checklist
                    } else {
                        localNetworkExplainer
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsGetServer) {
            ZStack {
                OnboardingBackground()
                VStack(alignment: .leading, spacing: 20) {
                    Text("Get GridStream Server for Mac").onboardingTitle()
                    GetServerPanel()
                }
                .padding(32)
            }
            .preferredColorScheme(.dark)
        }
        .task(id: demoController.allowsBrowsing) {
            guard demoController.allowsBrowsing else { return }
            try? await Task.sleep(for: tipsDelay)
            withAnimation { showsTips = true }
        }
    }

    // MARK: - Before the system prompt

    private var localNetworkExplainer: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "wifi")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect my Mac").onboardingEyebrow()
                Text("Find your Mac on this network").onboardingTitle()
                Text("GridStream looks for GridStream Server on your Wi-Fi. iPadOS then asks to let GridStream find devices on your local network: choose Allow.")
                    .onboardingBody()
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Not now") {
                    demoController.flow = nil
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Button("Find my Mac") {
                    demoController.findMac(discovery: discoveryService)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
        }
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connect my Mac").onboardingEyebrow()
                Text(isUnlocked && server != nil ? "Your Mac is connected" : "Connecting to your Mac")
                    .onboardingTitle()
            }

            VStack(alignment: .leading, spacing: 18) {
                step(
                    state: server != nil ? .done : .active,
                    title: "Looking on your local network",
                    detail: server == nil ? "Make sure GridStream Server is open on your Mac." : nil
                )
                step(
                    state: server != nil ? .done : .waiting,
                    title: server.map { "Found \($0.name)" } ?? "GridStream Server found",
                    detail: nil
                )
                step(
                    state: server == nil ? .waiting : (isUnlocked ? .done : .active),
                    title: "Unlocked with the PIN",
                    detail: server != nil && !isUnlocked ? "Enter the PIN shown in the GridStream menu on your Mac's menu bar." : nil
                )
            }

            if server != nil {
                Button(isUnlocked ? "Start" : "Enter PIN") {
                    demoController.flow = nil
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            } else if showsTips {
                tips
            } else {
                Button("Close") {
                    demoController.flow = nil
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No Mac found yet")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                tip("Open GridStream Server on your Mac.")
                tip("Put the Mac and this iPad on the same Wi-Fi network.")
                tip("Allow GridStream in Settings › Privacy & Security › Local Network.")
            }

            HStack(spacing: 12) {
                Button("Get the server") {
                    showsGetServer = true
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Button("Try the demo") {
                    demoController.tryDemo(discovery: discoveryService, gridState: gridState)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
        }
        .padding(20)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.opacity)
    }

    private func tip(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.78))
    }

    private enum StepState {
        case waiting, active, done
    }

    private func step(state: StepState, title: LocalizedStringKey, detail: LocalizedStringKey?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                case .active:
                    ProgressView()
                        .tint(.white)
                case .waiting:
                    Image(systemName: "circle")
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .font(.title3)
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(state == .waiting ? 0.5 : 1))
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
