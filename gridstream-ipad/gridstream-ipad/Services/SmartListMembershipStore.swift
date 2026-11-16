//
//  SmartListMembershipStore.swift
//  gridstream-ipad
//

import Foundation
import OSLog

/// App-wide cache of smart-list membership (`fileId` -> smart list IDs).
///
/// Smart-list membership is evaluated server-side (from each list's criteria),
/// so unlike simple lists it cannot be derived on the client. The full map is
/// fetched once and shared across all tiles — mirroring the web app — and
/// refreshed after mutations that can change membership (e.g. rating changes).
@MainActor
@Observable
final class SmartListMembershipStore {
    static let shared = SmartListMembershipStore()

    /// `fileId` -> smart list IDs the video belongs to.
    private(set) var memberships: [String: [UUID]] = [:]

    private var hasLoaded = false
    private var isLoading = false
    private let service: SmartListService

    init(service: SmartListService? = nil) {
        self.service = service ?? SmartListService()
    }

    /// Smart list IDs the given video belongs to.
    func smartListIds(forFileId fileId: String) -> [UUID] {
        memberships[fileId] ?? []
    }

    /// Loads the membership map. The first call fetches; subsequent calls are
    /// no-ops unless `force` is set (used to refresh after a mutation). Concurrent
    /// callers (e.g. every tile on appear) coalesce onto a single fetch so the
    /// server evaluates all smart-list criteria only once.
    func load(from serverURL: URL, force: Bool = false) async {
        if isLoading && !force { return }
        if hasLoaded && !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            memberships = try await service.fetchMemberships(from: serverURL)
            hasLoaded = true
        } catch {
            AppLogger.video.error("Failed to load smart list memberships: \(error.localizedDescription)")
        }
    }
}
