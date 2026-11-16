    //
//  gridstream_ipadApp.swift
//  gridstream-ipad
//
//  Created by Andre Frelicot on 18/12/2025.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct gridstream_ipadApp: App {
    @State private var gridState = GridState()
    @State private var discoveryService: ServerDiscoveryService
    @State private var serverSessionManager = ServerSessionManager.shared
    @State private var videoHistoryManager = VideoHistoryManager()
    @State private var sharedPlayerPool = SharedPlayerPool()
    @State private var catalogStatusManager = CatalogStatusManager()
    @State private var demoController: DemoController
    @State private var persistenceService: LayoutPersistenceService?
    @State private var sourcePresetService: SourcePresetService?
    @State private var hasAttemptedPhase2Restore = false
    @State private var showsLayoutStoreAlert: Bool
    @State private var layoutStoreResetMessage: String?

    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer
    private let usesInMemoryPersistenceFallback: Bool
    private let layoutStoreFailure: String?

    init() {
        let store = LayoutStore.open()
        modelContainer = store.container
        layoutStoreFailure = store.failure
        usesInMemoryPersistenceFallback = store.failure != nil
        _showsLayoutStoreAlert = State(initialValue: store.failure != nil)

        // Browsing stays off until the user asks to find their Mac; set it
        // before the first scene phase change can restart discovery.
        let discoveryService = ServerDiscoveryService()
        let demoController = DemoController()
        discoveryService.isBrowsingEnabled = demoController.allowsBrowsing
        _discoveryService = State(initialValue: discoveryService)
        _demoController = State(initialValue: demoController)

        // Requests to the demo host from `URLSession.shared` (AsyncImage) are
        // answered in the app, like those of the API session.
        URLProtocol.registerClass(DemoURLProtocol.self)

        // Initialize audio normalization settings on app launch
        // This ensures persisted settings are applied to the shared processor
        _ = AudioNormalizationSettingsManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(gridState)
                .environment(discoveryService)
                .environment(serverSessionManager)
                .environment(GlobalPlaybackManager.shared)
                .environment(videoHistoryManager)
                .environment(sharedPlayerPool)
                .environment(catalogStatusManager)
                .environment(sourcePresetService)
                .environment(demoController)
                .onAppear {
                    setupPersistence()
                    demoController.start(discovery: discoveryService)
                }
                // The persistent layout store could not be opened: say so
                // instead of silently dropping every layout change.
                .alert("Saved Layouts Unavailable", isPresented: $showsLayoutStoreAlert) {
                    Button("Reset Saved Layouts", role: .destructive) {
                        resetLayoutStore()
                    }
                    Button("Continue Without Saving", role: .cancel) {}
                } message: {
                    Text("GridStream couldn't open its saved layouts (\(layoutStoreFailure ?? String(localized: "unknown error"))). Changes made now won't be kept. Resetting deletes the saved layouts and presets; relaunch the app afterwards.")
                }
                .alert(
                    "Saved Layouts",
                    isPresented: Binding(
                        get: { layoutStoreResetMessage != nil },
                        set: { if !$0 { layoutStoreResetMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(layoutStoreResetMessage ?? "")
                }
                .onChange(of: discoveryService.verifiedActiveServer) { _, _ in
                    configureServerServices()
                }
                .onChange(of: serverSessionManager.isAuthorized) { _, _ in
                    configureServerServices()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    catalogStatusManager.updateScenePhase(newPhase)

                    if newPhase == .active && oldPhase != .active {
                        // Try the last-known server first for instant reconnect,
                        // then restart Bonjour discovery as a background fallback.
                        discoveryService.validateLastKnownServer()
                        discoveryService.restartDiscovery()
                    } else if newPhase == .background {
                        GridSidecarStateCoordinator.captureContentState(
                            gridState: gridState,
                            playerPool: sharedPlayerPool
                        )
                        gridState.flushPendingSave()
                        discoveryService.stopDiscovery()
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    /// Points the catalog services at the active server — only once it is
    /// reachable *and* the session is authorized. Without a session, polling
    /// and catalog fetches only produce 401s (which used to feed a
    /// lock/rediscovery loop), so they stay suspended until login.
    private func configureServerServices() {
        guard let serverURL = discoveryService.verifiedActiveServer?.url,
              serverSessionManager.isAuthorized else {
            catalogStatusManager.suspend()
            return
        }

        Task {
            await videoHistoryManager.configure(serverURL: serverURL)
        }
        catalogStatusManager.configure(serverURL: serverURL)
        runPhase2RestoreIfNeeded(serverURL: serverURL)
    }

    private func runPhase2RestoreIfNeeded(serverURL: URL) {
        guard !hasAttemptedPhase2Restore,
              gridState.hasPendingRestores else { return }

        hasAttemptedPhase2Restore = true
        Task { @MainActor in
            await GridSidecarStateCoordinator.restoreContentAfterDiscovery(
                serverURL: serverURL,
                gridState: gridState,
                historyManager: videoHistoryManager
            )
        }
    }

    private func resetLayoutStore() {
        do {
            try LayoutStore.resetPersistentStore()
            layoutStoreResetMessage = String(localized: "Saved layouts were reset. Quit and reopen GridStream to start saving again.")
        } catch {
            layoutStoreResetMessage = String(localized: "Couldn't reset saved layouts: \(error.localizedDescription)")
        }
    }

    private func setupPersistence() {
        guard persistenceService == nil else { return }

        let context = modelContainer.mainContext
        let service = LayoutPersistenceService(modelContext: context)
        persistenceService = service
        gridState.connectPersistence(service)
        if usesInMemoryPersistenceFallback {
            AppLogger.grid.warning("Using in-memory layout persistence fallback for this launch")
        }

        // Initialize source preset service
        sourcePresetService = SourcePresetService(modelContext: context)

        // Mirror audio state mutations into SwiftData so mute/solo/override
        // survive cold starts.
        TileAudioStateManager.shared.persistenceBridge = { [weak gridState] index, state in
            gridState?.persistTileAudioState(at: index, state: state)
        }

        // When the session expires, refresh discovery as well — a 401 often
        // means the server restarted, in which case Bonjour may have a
        // stale record.
        serverSessionManager.onSessionExpired = { [weak discoveryService] _ in
            discoveryService?.validateLastKnownServer()
            discoveryService?.restartDiscovery()
        }
    }
}
