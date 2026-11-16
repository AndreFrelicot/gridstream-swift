//
//  DemoPackDownloaderTests.swift
//  gridstream-ipadTests
//

import CryptoKit
import XCTest
@testable import gridstream_ipad

/// Serves a fake demo pack from memory.
nonisolated final class DemoPackStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var files: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "pack.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let path = String(url.path.dropFirst("/demo/".count))
        let data = Self.files[path]
        let response = HTTPURLResponse(url: url, statusCode: data == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class DemoPackDownloaderTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DemoPackDownloaderTests-\(UUID().uuidString)")
        DemoPackStubProtocol.files = [:]
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        DemoPackStubProtocol.files = [:]
    }

    private var pack: URL { root.appendingPathComponent("v1") }

    private func makeDownloader() -> DemoPackDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoPackStubProtocol.self]
        let root = root!
        return DemoPackDownloader(
            session: URLSession(configuration: configuration),
            baseURL: { URL(string: "https://pack.test/demo/")! },
            rootDirectory: { root },
            packDirectory: { root.appendingPathComponent("v1") }
        )
    }

    private func entry(_ path: String, _ data: Data) -> [String: Any] {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ["path": path, "size": data.count, "sha256": hash]
    }

    /// Serves `files` and a manifest listing them (the manifest may lie).
    private func serve(_ files: [String: Data], listed: [[String: Any]]? = nil) throws {
        let entries = listed ?? files.keys.sorted().map { entry($0, files[$0]!) }
        DemoPackStubProtocol.files = files
        DemoPackStubProtocol.files["manifest.json"] = try JSONSerialization.data(withJSONObject: ["version": 1, "files": entries])
    }

    private func waitUntilDone(_ downloader: DemoPackDownloader) async throws {
        for _ in 0..<200 {
            switch downloader.phase {
            case .installed, .failed:
                return
            default:
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        XCTFail("The download did not finish")
    }

    func testDownloadsChecksAndInstallsThePack() async throws {
        let clip = Data(repeating: 7, count: 100_000)
        let seed = Data(#"{"catalogVersion":1}"#.utf8)
        try serve(["clips/abc.mp4": clip, "seed.json": seed])
        let downloader = makeDownloader()

        await downloader.fetchManifest()
        guard case .ready(let manifest) = downloader.phase else {
            return XCTFail("Expected the manifest, got \(downloader.phase)")
        }
        XCTAssertEqual(manifest.clipCount, 1)
        XCTAssertEqual(manifest.totalSize, Int64(clip.count + seed.count))

        downloader.start()
        try await waitUntilDone(downloader)

        XCTAssertEqual(downloader.phase, .installed)
        XCTAssertEqual(try Data(contentsOf: pack.appendingPathComponent("clips/abc.mp4")), clip)
        XCTAssertEqual(try Data(contentsOf: pack.appendingPathComponent("seed.json")), seed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pack.appendingPathComponent("manifest.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("download-v1").path))
        XCTAssertEqual(downloader.clipsDone, 1)
        XCTAssertEqual(downloader.fractionCompleted, 1)
    }

    func testDamagedFileFailsWithoutInstalling() async throws {
        let clip = Data(repeating: 1, count: 1_000)
        var listed = entry("clips/abc.mp4", Data(repeating: 2, count: 1_000))
        listed["size"] = clip.count
        let seed = Data("{}".utf8)
        try serve(["clips/abc.mp4": clip, "seed.json": seed], listed: [listed, entry("seed.json", seed)])
        let downloader = makeDownloader()

        await downloader.fetchManifest()
        downloader.start()
        for _ in 0..<200 where downloader.phase == .downloading {
            try await Task.sleep(for: .milliseconds(50))
        }

        guard case .failed = downloader.phase else {
            return XCTFail("Expected a failure, got \(downloader.phase)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: pack.path))
    }

    func testRejectsAManifestWithUnsafePaths() async throws {
        let data = Data("x".utf8)
        try serve(["clips/a.mp4": data], listed: [entry("../escape.mp4", data)])
        let downloader = makeDownloader()

        await downloader.fetchManifest()

        guard case .failed = downloader.phase else {
            return XCTFail("Expected a failure, got \(downloader.phase)")
        }
    }

    func testRejectsInvalidManifestFieldsBeforeShowingDownloadSize() async throws {
        let data = Data("x".utf8)
        let valid = entry("seed.json", data)
        var cases: [[[String: Any]]] = []
        for size: Int64 in [-1, Int64.max, DemoPackManifest.maximumFileSize + 1] {
            var file = valid
            file["size"] = size
            cases.append([file])
        }
        var badHash = valid
        badHash["sha256"] = "not-a-checksum"
        cases += [[badHash], [valid, valid], [entry("manifest.json", data)], [entry("clips/%2e%2e.mp4", data)]]
        for listed in cases {
            try serve(["seed.json": data], listed: listed)
            let downloader = makeDownloader()
            await downloader.fetchManifest()
            guard case .failed = downloader.phase else {
                XCTFail("Accepted invalid manifest: \(listed)")
                continue
            }
            XCTAssertEqual(downloader.totalBytes, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: pack.path))
        }
    }

    func testManifestRejectsUnsupportedVersionAndExcessiveTotal() {
        let file = DemoPackManifest.File(path: "seed.json", size: 1, sha256: String(repeating: "a", count: 64))
        XCTAssertFalse(DemoPackManifest(version: 2, files: [file]).isValid)
        let large = (0..<5).map {
            DemoPackManifest.File(path: "clips/clip-\($0).mp4", size: DemoPackManifest.maximumFileSize, sha256: file.sha256)
        }
        let manifest = DemoPackManifest(version: 1, files: [file] + large)
        XCTAssertFalse(manifest.isValid)
        XCTAssertEqual(manifest.totalSize, 0)
    }

    func testMissingManifestFails() async throws {
        let downloader = makeDownloader()

        await downloader.fetchManifest()

        guard case .failed = downloader.phase else {
            return XCTFail("Expected a failure, got \(downloader.phase)")
        }
    }
}

@MainActor
final class DemoControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "DemoControllerTests"

    override func setUp() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func testFirstLaunchShowsOnboardingWithoutBrowsing() async {
        let controller = DemoController(defaults: defaults)
        let discovery = ServerDiscoveryService()

        controller.start(discovery: discovery)

        XCTAssertEqual(controller.flow, .onboarding)
        XCTAssertFalse(controller.allowsBrowsing)
        XCTAssertFalse(discovery.isBrowsingEnabled)
    }

    func testExistingUsersSkipOnboardingAndKeepBrowsing() async {
        defaults.set(Data("{}".utf8), forKey: DemoController.lastKnownServerKey)

        let controller = DemoController(defaults: defaults)

        XCTAssertTrue(controller.hasCompletedOnboarding)
        XCTAssertTrue(controller.allowsBrowsing)
    }

    func testDemoUsersDoNotGetBrowsingOnTheNextLaunch() async {
        let first = DemoController(defaults: defaults)
        first.finishOnboarding()
        // Opening the demo remembers it as the last server.
        defaults.set(Data("{}".utf8), forKey: DemoController.lastKnownServerKey)

        let next = DemoController(defaults: defaults)

        XCTAssertTrue(next.hasCompletedOnboarding)
        XCTAssertFalse(next.allowsBrowsing)
    }

    func testFindMacEnablesBrowsingForGood() async {
        let controller = DemoController(defaults: defaults)
        let discovery = ServerDiscoveryService()
        discovery.isBrowsingEnabled = false

        controller.findMac(discovery: discovery)
        discovery.stopDiscovery()

        XCTAssertTrue(discovery.isBrowsingEnabled)
        XCTAssertTrue(DemoController(defaults: defaults).allowsBrowsing)
    }
}
