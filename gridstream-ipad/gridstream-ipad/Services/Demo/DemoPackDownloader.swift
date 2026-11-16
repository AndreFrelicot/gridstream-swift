//
//  DemoPackDownloader.swift
//  gridstream-ipad
//
//  Downloads the demo pack: the manifest first (to show its size), then
//  every file into a staging folder, each checked against its SHA-256.
//  The staging folder becomes the pack folder in one move once complete,
//  so a pack is either fully installed or absent. Files already staged
//  and intact are kept, so an interrupted download resumes.
//

import CryptoKit
import Foundation
import Observation

@Observable
final class DemoPackDownloader {
    enum Phase: Equatable {
        case idle
        case fetchingManifest
        case ready(DemoPackManifest)
        case downloading
        case installed
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var bytesDone: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var clipsDone = 0
    private(set) var clipCount = 0

    var fractionCompleted: Double {
        totalBytes > 0 ? min(Double(bytesDone) / Double(totalBytes), 1) : 0
    }

    private var manifest: DemoPackManifest?
    private var downloadTask: Task<Void, Never>?
    private let session: URLSession
    private let baseURL: () -> URL
    private let rootDirectory: () -> URL
    private let packDirectory: () -> URL
    private static let attempts = 3

    init(
        session: URLSession = URLSession(configuration: .ephemeral),
        baseURL: @escaping () -> URL = { DemoPack.baseURL },
        rootDirectory: @escaping () -> URL = { DemoPack.rootDirectory },
        packDirectory: @escaping () -> URL = { DemoPack.packDirectory }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.rootDirectory = rootDirectory
        self.packDirectory = packDirectory
    }

    // Nonisolated on purpose, see `DemoController`'s deinit.
    deinit {}

    private var stagingDirectory: URL {
        rootDirectory().appendingPathComponent("download-\(DemoPack.versionFolder)", isDirectory: true)
    }

    // MARK: - Manifest

    /// Fetches the manifest unless it is known or on its way. Not tied to a
    /// view's lifetime: a cover switching flows would cancel a view's task.
    func prepare() {
        switch phase {
        case .idle, .failed:
            Task { await fetchManifest() }
        case .fetchingManifest, .ready, .downloading, .installed:
            break
        }
    }

    /// Fetches the manifest so the size can be shown before downloading.
    func fetchManifest() async {
        if case .downloading = phase { return }
        phase = .fetchingManifest
        do {
            let url = baseURL().appendingPathComponent("manifest.json")
            let (data, response) = try await session.data(from: url)
            try Self.checkStatus(response)
            let manifest = try JSONDecoder().decode(DemoPackManifest.self, from: data)
            guard manifest.isValid else {
                throw DownloadError.invalidManifest
            }
            self.manifest = manifest
            phase = .ready(manifest)
        } catch is CancellationError {
            phase = .idle
        } catch let error as URLError where error.code == .cancelled {
            phase = .idle
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Forgets the manifest and progress, after the pack was deleted.
    func reset() {
        downloadTask?.cancel()
        manifest = nil
        phase = .idle
        bytesDone = 0
        clipsDone = 0
    }

    // MARK: - Download

    /// Downloads and installs the pack whose manifest was fetched.
    func start() {
        guard let manifest, downloadTask == nil else { return }
        phase = .downloading
        totalBytes = manifest.totalSize
        clipCount = manifest.clipCount
        bytesDone = 0
        clipsDone = 0

        downloadTask = Task {
            do {
                try await install(manifest)
                phase = .installed
            } catch is CancellationError {
                phase = .ready(manifest)
            } catch let error as URLError where error.code == .cancelled {
                phase = .ready(manifest)
            } catch {
                phase = .failed(Self.message(for: error))
            }
            downloadTask = nil
        }
    }

    /// Stops the download. Files already checked stay staged for a resume.
    func cancel() {
        downloadTask?.cancel()
    }

    private func install(_ manifest: DemoPackManifest) async throws {
        guard manifest.isValid else { throw DownloadError.invalidManifest }
        try DemoPack.prepareRootDirectory(at: rootDirectory())
        let staging = stagingDirectory
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Self.checkFreeSpace(for: manifest, stagingDirectory: staging)

        // The manifest goes last: its presence marks a complete pack.
        let files = manifest.files
        for file in files {
            try Task.checkCancellation()
            let target = staging.appendingPathComponent(file.path)
            let fileStart = bytesDone
            if try await !Self.isIntact(target, file) {
                try await download(file, to: target, progressBase: fileStart)
            }
            bytesDone = fileStart + file.size
            if file.path.hasPrefix("clips/") {
                clipsDone += 1
            }
        }

        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)

        let fileManager = FileManager.default
        let pack = packDirectory()
        if fileManager.fileExists(atPath: pack.path) {
            try fileManager.removeItem(at: pack)
        }
        try fileManager.moveItem(at: staging, to: pack)
        await DemoServer.shared.unload()
    }

    private func download(_ file: DemoPackManifest.File, to target: URL, progressBase: Int64) async throws {
        let url = baseURL().appendingPathComponent(file.path)
        var lastError: Error = DownloadError.checksumMismatch(file.path)
        for attempt in 1...Self.attempts {
            try Task.checkCancellation()
            do {
                try await fetch(url, to: target) { [weak self] received in
                    self?.bytesDone = progressBase + min(received, file.size)
                }
                if try await Self.isIntact(target, file) {
                    return
                }
                lastError = DownloadError.checksumMismatch(file.path)
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
            try? FileManager.default.removeItem(at: target)
            if attempt < Self.attempts {
                try await Task.sleep(for: .seconds(attempt))
            }
        }
        throw lastError
    }

    /// Downloads `url` to `target`, reporting received bytes while it runs.
    private func fetch(_ url: URL, to target: URL, progress: @escaping (Int64) -> Void) async throws {
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let handle = DownloadHandle()
        let monitor = Task {
            while !Task.isCancelled {
                progress(handle.bytesReceived)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { monitor.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: url) { location, response, error in
                    // The temporary file is deleted when this handler returns.
                    do {
                        if let error { throw error }
                        try Self.checkStatus(response)
                        guard let location else { throw URLError(.badServerResponse) }
                        try? FileManager.default.removeItem(at: target)
                        try FileManager.default.moveItem(at: location, to: target)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                handle.set(task)
                task.resume()
            }
        } onCancel: {
            handle.cancel()
        }
    }

    /// The running download task, shared with the progress monitor and the
    /// cancellation handler.
    private nonisolated final class DownloadHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDownloadTask?
        private var isCancelled = false

        func set(_ task: URLSessionDownloadTask) {
            let cancelled = lock.withLock {
                self.task = task
                return isCancelled
            }
            if cancelled { task.cancel() }
        }

        var bytesReceived: Int64 {
            lock.withLock { task?.countOfBytesReceived ?? 0 }
        }

        func cancel() {
            let task = lock.withLock {
                isCancelled = true
                return self.task
            }
            task?.cancel()
        }
    }

    // MARK: - Checks

    private nonisolated static func isIntact(_ url: URL, _ file: DemoPackManifest.File) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  Int64(size) == file.size else { return false }
            return try sha256(of: url) == file.sha256.lowercased()
        }.value
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func checkStatus(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.http(http.statusCode)
        }
    }

    private static func checkFreeSpace(for manifest: DemoPackManifest, stagingDirectory: URL) throws {
        let values = try? stagingDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        let needed = manifest.totalSize + 50_000_000
        if available < needed {
            throw DownloadError.notEnoughSpace(needed)
        }
    }

    private enum DownloadError: LocalizedError {
        case invalidManifest
        case http(Int)
        case checksumMismatch(String)
        case notEnoughSpace(Int64)

        var errorDescription: String? {
            switch self {
            case .invalidManifest:
                return String(localized: "The demo download is not available right now.")
            case .http(let status):
                return String(localized: "The demo server answered with error \(status).")
            case .checksumMismatch:
                return String(localized: "A demo file arrived damaged. Try again.")
            case .notEnoughSpace(let bytes):
                let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                return String(localized: "Not enough storage: the demo needs \(size) free.")
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return String(localized: "No internet connection. Connect and try again.")
            case .timedOut:
                return String(localized: "The download timed out. Try again.")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
