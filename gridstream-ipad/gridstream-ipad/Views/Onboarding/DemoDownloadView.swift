//
//  DemoDownloadView.swift
//  gridstream-ipad
//
//  Asks before downloading the demo (with its size, App Review 4.2.3),
//  shows the progress, then opens the demo.
//

import SwiftUI

struct DemoDownloadView: View {
    @Environment(DemoController.self) private var demoController
    @Environment(ServerDiscoveryService.self) private var discoveryService
    @Environment(GridState.self) private var gridState

    private var downloader: DemoPackDownloader { demoController.downloader }

    var body: some View {
        ZStack {
            OnboardingBackground()

            OnboardingCard(maxWidth: 520) {
                switch downloader.phase {
                case .idle, .fetchingManifest:
                    consent(manifest: nil)
                case .ready(let manifest):
                    consent(manifest: manifest)
                case .downloading:
                    progress
                case .installed:
                    VStack(spacing: 16) {
                        ProgressView().tint(.white)
                        Text("Opening the demo…").onboardingBody()
                    }
                    .frame(maxWidth: .infinity)
                case .failed(let message):
                    failure(message)
                }
            }
            .padding(32)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            downloader.prepare()
        }
        .onChange(of: downloader.phase) { _, phase in
            guard phase == .installed else { return }
            demoController.activateDemo(discovery: discoveryService, gridState: gridState)
            demoController.flow = nil
        }
    }

    private func consent(manifest: DemoPackManifest?) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Demo").onboardingEyebrow()
                Text("Download the demo?").onboardingTitle()
                Text(consentText(manifest)).onboardingBody()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("Clips from Blender Foundation open movies (CC BY). Stored on this iPad until you delete them from the server menu.", systemImage: "film.stack")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Not now") {
                    demoController.flow = nil
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Button {
                    downloader.start()
                } label: {
                    if manifest == nil {
                        ProgressView().tint(.black)
                    } else {
                        Text("Download")
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(manifest == nil)
            }
        }
    }

    private func consentText(_ manifest: DemoPackManifest?) -> String {
        guard let manifest else {
            return String(localized: "GridStream downloads a few short clips with a ready-made library, so you can try every feature without a Mac.")
        }
        let size = ByteCountFormatter.string(fromByteCount: manifest.totalSize, countStyle: .file)
        return String(localized: "GridStream downloads \(manifest.clipCount) short clips (\(size)) with a ready-made library, so you can try every feature without a Mac. Wi-Fi recommended.")
    }

    private var progress: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: downloader.fractionCompleted)
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: downloader.fractionCompleted)
                Text(downloader.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 6) {
                Text("Downloading the demo")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(progressText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }

            Button("Cancel") {
                downloader.cancel()
            }
            .buttonStyle(OnboardingSecondaryButtonStyle())
            .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
    }

    private var progressText: String {
        let done = ByteCountFormatter.string(fromByteCount: downloader.bytesDone, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: downloader.totalBytes, countStyle: .file)
        let clip = min(downloader.clipsDone + 1, downloader.clipCount)
        return String(localized: "Clip \(clip) of \(downloader.clipCount) · \(done) of \(total)")
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Demo").onboardingEyebrow()
                Text("The download stopped").onboardingTitle()
                Text(message).onboardingBody()
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("Not now") {
                    demoController.flow = nil
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Button("Try again") {
                    Task { await downloader.fetchManifest() }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
        }
    }
}
