//
//  OnboardingView.swift
//  gridstream-ipad
//
//  First launch: what GridStream does, how the Mac and the iPad split the
//  work, where to get the server, then a choice between connecting to a
//  Mac and trying the demo.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(DemoController.self) private var demoController
    @Environment(ServerDiscoveryService.self) private var discoveryService
    @Environment(GridState.self) private var gridState

    @State private var page = 0
    private let lastPage = 3

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 24) {
                TabView(selection: $page) {
                    manyVideosPage.tag(0)
                    macAndIPadPage.tag(1)
                    getServerPage.tag(2)
                    choicePage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                if page < lastPage {
                    Button("Continue") {
                        withAnimation { page += 1 }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .frame(maxWidth: 320)
                }
            }
            .padding(.vertical, 40)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var manyVideosPage: some View {
        page(
            eyebrow: "Welcome to GridStream",
            title: "Watch many videos at once",
            text: "Play several videos together in one grid and keep an eye on all of them. Scrub frame by frame, rate, tag and annotate as they play."
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 10), count: 3), spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(index == 1 ? 0.32 : 0.14))
                        .frame(height: 68)
                        .overlay {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                }
            }
        }
    }

    private var macAndIPadPage: some View {
        page(
            eyebrow: "How it works",
            title: "Your Mac serves, your iPad plays",
            text: "GridStream Server runs on your Mac and shares your video folders with this iPad."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    Image(systemName: "desktopcomputer")
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "ipad.landscape")
                }
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

                featureRow("lock.shield", title: "Stays on your Mac", text: "Your videos are streamed, never uploaded or copied.")
                featureRow("wifi", title: "Local network only", text: "No account and no cloud: the iPad talks to your Mac directly.")
            }
        }
    }

    private var getServerPage: some View {
        page(
            eyebrow: "On your Mac",
            title: "Get GridStream Server for Mac",
            text: "Install it on the Mac that holds your videos. Send yourself the link to download it there."
        ) {
            GetServerPanel()
        }
    }

    private var choicePage: some View {
        page(
            eyebrow: "Ready",
            title: "How do you want to start?",
            text: "You can switch between your Mac and the demo at any time from the server menu, where you will also find Help."
        ) {
            HStack(alignment: .top, spacing: 16) {
                choiceCard(
                    symbol: "desktopcomputer",
                    title: "Connect to my Mac",
                    text: "Find GridStream Server on this network.",
                    action: "Find my Mac"
                ) {
                    demoController.finishOnboarding()
                    demoController.flow = .connectMac
                }

                choiceCard(
                    symbol: "play.rectangle.on.rectangle",
                    title: "Try the demo",
                    text: "Short clips from open movies, ready to play. No Mac needed.",
                    action: "Download demo"
                ) {
                    demoController.finishOnboarding()
                    demoController.tryDemo(discovery: discoveryService, gridState: gridState)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func page<Content: View>(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        text: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            OnboardingCard(maxWidth: 640) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(eyebrow).onboardingEyebrow()
                        Text(title).onboardingTitle()
                        Text(text).onboardingBody()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content()
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
    }

    private func featureRow(_ symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func choiceCard(
        symbol: String,
        title: LocalizedStringKey,
        text: LocalizedStringKey,
        action: LocalizedStringKey,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action, action: perform)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
