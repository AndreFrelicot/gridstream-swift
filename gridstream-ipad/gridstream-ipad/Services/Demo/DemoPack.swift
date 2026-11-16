//
//  DemoPack.swift
//  gridstream-ipad
//
//  Where the demo pack lives on the iPad, and what its manifest says.
//
//  Layout of `Application Support/Demo` (excluded from backup):
//    v1/manifest.json         written last: its presence means "installed"
//    v1/seed.json             the initial DemoStore
//    v1/clips/<fileId>.mp4
//    v1/thumbnails/<fileId>.jpg
//    v1/CREDITS.md
//    state.json               the demo's current state (seed + user changes)
//    captures/<id>.jpg        frames captured in the demo
//

import Foundation

/// `manifest.json` of a demo pack: every file with its size and SHA-256.
nonisolated struct DemoPackManifest: Codable, Sendable, Equatable {
    struct File: Codable, Sendable, Equatable {
        let path: String
        let size: Int64
        let sha256: String
    }

    let version: Int
    let files: [File]

    static let maximumFileSize: Int64 = 512 * 1_024 * 1_024
    static let maximumPackSize: Int64 = 2 * 1_024 * 1_024 * 1_024
    static let maximumFileCount = 2_048

    /// Invalid manifests never participate in unchecked size arithmetic.
    var totalSize: Int64 { validatedTotalSize ?? 0 }

    var clipCount: Int {
        files.filter { $0.path.hasPrefix("clips/") }.count
    }

    var hasSafePaths: Bool {
        files.allSatisfy { Self.isAllowedPath($0.path) }
    }

    var isValid: Bool { validatedTotalSize != nil }

    private var validatedTotalSize: Int64? {
        guard version == 1, !files.isEmpty, files.count <= Self.maximumFileCount,
              hasSafePaths, files.contains(where: { $0.path == "seed.json" }) else { return nil }
        var paths: Set<String> = []
        var total: Int64 = 0
        for file in files {
            guard paths.insert(file.path.lowercased()).inserted,
                  (0...Self.maximumFileSize).contains(file.size),
                  file.sha256.utf8.count == 64,
                  file.sha256.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
            // Both operands are bounded before addition; no Int64 overflow.
            guard file.size <= Self.maximumPackSize - total else { return nil }
            total += file.size
        }
        return total
    }

    private static func isAllowedPath(_ path: String) -> Bool {
        if path == "seed.json" || path == "CREDITS.md" { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let suffix: String
        switch parts[0] {
        case "clips": suffix = ".mp4"
        case "thumbnails": suffix = ".jpg"
        default: return false
        }
        guard parts[1].hasSuffix(suffix) else { return false }
        let name = parts[1].dropLast(suffix.count)
        return !name.isEmpty && name.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

}

nonisolated enum DemoPack {
    /// Folder of the pack version this build reads.
    static let versionFolder = "v1"

    /// Where the pack is downloaded from. A `DemoPackBaseURL` user default
    /// (a launch argument works: `-DemoPackBaseURL http://localhost:8765/`)
    /// overrides it, to test a pack served from the Mac.
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "DemoPackBaseURL"),
           let url = URL(string: override) {
            return url
        }
        return defaultBaseURL
    }

    static let defaultBaseURL = URL(string: "https://videos.andrefrelicot.dev/gridstream/demo/v1/")!

    static var rootDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Demo", isDirectory: true)
    }

    static var packDirectory: URL {
        rootDirectory.appendingPathComponent(versionFolder, isDirectory: true)
    }

    static var stateURL: URL {
        rootDirectory.appendingPathComponent("state.json")
    }

    static var capturesDirectory: URL {
        rootDirectory.appendingPathComponent("captures", isDirectory: true)
    }

    static var manifestURL: URL {
        packDirectory.appendingPathComponent("manifest.json")
    }

    static var seedURL: URL {
        packDirectory.appendingPathComponent("seed.json")
    }

    static var creditsURL: URL {
        packDirectory.appendingPathComponent("CREDITS.md")
    }

    /// True once every file of the pack was downloaded and checked.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    static var installedManifest: DemoPackManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        guard let manifest = try? JSONDecoder().decode(DemoPackManifest.self, from: data), manifest.isValid else { return nil }
        return manifest
    }

    static func clipURL(forFileId fileId: String) -> URL? {
        existingFile("clips/\(fileId).mp4")
    }

    static func thumbnailURL(forFileId fileId: String) -> URL? {
        existingFile("thumbnails/\(fileId).jpg")
    }

    /// Deletes the pack and the demo's state.
    static func delete() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.removeItem(at: rootDirectory)
        }
    }

    /// Creates the root folder, excluded from iCloud and device backups.
    static func prepareRootDirectory(at root: URL = rootDirectory) throws {
        var root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }

    private static func existingFile(_ relativePath: String) -> URL? {
        // fileIds are hex; anything else is not a pack file.
        guard !relativePath.contains("..") else { return nil }
        let url = packDirectory.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
