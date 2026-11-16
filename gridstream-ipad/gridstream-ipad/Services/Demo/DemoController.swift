//
//  DemoController.swift
//  gridstream-ipad
//
//  The app-level flows around servers: the first-launch onboarding, the
//  "Connect my Mac" checklist, the demo download, and switching between
//  the demo and a real server.
//
//  Bonjour browsing triggers the system's Local Network prompt, so it only
//  starts once the user asked to find their Mac (or already has a server
//  from before onboarding existed).
//

import Foundation
import Observation

@Observable
final class DemoController {
    enum Flow: String, Identifiable {
        case onboarding
        case connectMac
        case demoDownload
        case credits
        case help

        var id: String { rawValue }
    }

    /// The flow presented over the grid, if any.
    var flow: Flow?

    /// Set when the demo starts: the grid fills its tiles once, then clears it.
    var pendingDemoFill = false

    let downloader = DemoPackDownloader()

    /// `DemoPack.isInstalled`, kept here so views see it change.
    private(set) var isPackInstalled = DemoPack.isInstalled

    private(set) var hasCompletedOnboarding: Bool
    private(set) var allowsBrowsing: Bool

    private let defaults: UserDefaults
    static let onboardingKey = "GridStreamOnboardingCompleted"
    static let browsingKey = "GridStreamLocalNetworkRequested"
    static let lastKnownServerKey = "GridStreamLastKnownServer"

    /// Where to get the Mac server.
    static let serverDownloadURL = URL(string: "https://andrefrelicot.dev/gridstream")!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Installs from before onboarding already know a server: skip it.
        if defaults.object(forKey: Self.onboardingKey) == nil,
           defaults.object(forKey: Self.lastKnownServerKey) != nil {
            defaults.set(true, forKey: Self.onboardingKey)
            defaults.set(true, forKey: Self.browsingKey)
        }
        hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)
        allowsBrowsing = defaults.bool(forKey: Self.browsingKey)
    }

    // An explicit deinit is nonisolated: the implicit one of a main-actor
    // class goes through the isolated-deinit back-deploy shim, which can
    // abort when the object is released outside a task (XCTest).
    deinit {}

    // MARK: - Launch

    /// Shows the onboarding on first launch, otherwise resumes where the
    /// user left: the demo, or browsing for their Mac.
    func start(discovery: ServerDiscoveryService) {
        discovery.isBrowsingEnabled = allowsBrowsing
        guard hasCompletedOnboarding else {
            flow = .onboarding
            return
        }
        // A demo remembered from the last launch reopens without browsing.
        if discovery.isDemoActive {
            if DemoPack.isInstalled {
                discovery.activateDemo()
            } else {
                discovery.deactivateDemo()
            }
        }
        discovery.startDiscovery()
    }

    func finishOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.onboardingKey)
    }

    /// Starts Bonjour browsing; the system asks for Local Network access
    /// the first time.
    func findMac(discovery: ServerDiscoveryService) {
        allowsBrowsing = true
        defaults.set(true, forKey: Self.browsingKey)
        discovery.isBrowsingEnabled = true
        discovery.startDiscovery()
    }

    // MARK: - Demo

    /// Opens the demo, downloading it first when needed.
    func tryDemo(discovery: ServerDiscoveryService, gridState: GridState) {
        if DemoPack.isInstalled {
            activateDemo(discovery: discovery, gridState: gridState)
            flow = nil
        } else {
            flow = .demoDownload
        }
    }

    func activateDemo(discovery: ServerDiscoveryService, gridState: GridState) {
        isPackInstalled = true
        guard !discovery.isDemoActive else { return }
        gridState.clearAllSources()
        discovery.activateDemo()
        pendingDemoFill = true
    }

    /// Leaves the demo and looks for the user's Mac.
    func exitDemo(discovery: ServerDiscoveryService, gridState: GridState) {
        leaveDemo(discovery: discovery, gridState: gridState)
        flow = .connectMac
    }

    /// Restores the demo catalog as it was downloaded.
    func resetDemo() async throws {
        try await DemoServer.shared.reset()
    }

    /// Deletes the downloaded videos and the demo's changes.
    func deleteDemo(discovery: ServerDiscoveryService, gridState: GridState) async throws {
        leaveDemo(discovery: discovery, gridState: gridState)
        await DemoServer.shared.unload()
        try DemoPack.delete()
        isPackInstalled = false
        downloader.reset()
    }

    private func leaveDemo(discovery: ServerDiscoveryService, gridState: GridState) {
        guard discovery.isDemoActive else { return }
        gridState.clearAllSources()
        pendingDemoFill = false
        discovery.deactivateDemo()
        if allowsBrowsing {
            discovery.startDiscovery()
        }
    }
}
