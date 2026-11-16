import Foundation
import xxHash_Swift

nonisolated enum FileHasherError: Error, Equatable {
    case fileTooSmall(size: Int64, minimum: Int64)
    case unableToReadFile(path: String)
    case fileNotFound(path: String)
}

actor FileHasher {
    /// Minimum file size required for hashing: 192KB (3 x 64KB chunks)
    static let minimumFileSize: Int64 = 196_608

    /// Size of each chunk to read: 64KB
    static let chunkSize: Int = 65_536

    /// Computes a unique file identifier based on partial file content hashing.
    ///
    /// The algorithm reads three 64KB chunks from the file (first, middle, last),
    /// computes xxHash64 on each chunk, then combines the three hashes with
    /// the file size into a final xxHash64.
    ///
    /// - Parameter url: The file URL to compute the hash for
    /// - Returns: A 16-character hex-encoded string representing the file ID
    /// - Throws: `FileHasherError.fileTooSmall` if file is under 192KB
    /// - Throws: `FileHasherError.unableToReadFile` if file cannot be read
    /// - Throws: `FileHasherError.fileNotFound` if file does not exist
    func computeFileId(for url: URL) async throws -> String {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw FileHasherError.fileNotFound(path: url.path)
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw FileHasherError.unableToReadFile(path: url.path)
        }

        guard fileSize >= Self.minimumFileSize else {
            throw FileHasherError.fileTooSmall(size: fileSize, minimum: Self.minimumFileSize)
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        // Read first 64KB chunk
        let firstChunk = try readChunk(from: fileHandle, at: 0, size: Self.chunkSize)

        // Calculate middle position: (fileSize / 2) - 32KB
        let middlePosition = UInt64(fileSize / 2) - UInt64(Self.chunkSize / 2)
        let middleChunk = try readChunk(from: fileHandle, at: middlePosition, size: Self.chunkSize)

        // Read last 64KB chunk
        let lastPosition = UInt64(fileSize) - UInt64(Self.chunkSize)
        let lastChunk = try readChunk(from: fileHandle, at: lastPosition, size: Self.chunkSize)

        // Compute xxHash64 on each chunk
        let firstHash = XXH64.digest(firstChunk)
        let middleHash = XXH64.digest(middleChunk)
        let lastHash = XXH64.digest(lastChunk)

        // Combine three hashes with file size into final hash
        let combinedData = combineHashesWithSize(
            firstHash: firstHash,
            middleHash: middleHash,
            lastHash: lastHash,
            fileSize: fileSize
        )
        let finalHash = XXH64.digest(combinedData)

        return String(format: "%016llx", finalHash)
    }

    /// Reads a chunk of data from the file at the specified offset
    private func readChunk(from fileHandle: FileHandle, at offset: UInt64, size: Int) throws -> Data {
        try fileHandle.seek(toOffset: offset)
        guard let data = try fileHandle.read(upToCount: size), data.count == size else {
            throw FileHasherError.unableToReadFile(path: "")
        }
        return data
    }

    /// Combines three hash values and file size into a single Data object for final hashing
    private func combineHashesWithSize(
        firstHash: UInt64,
        middleHash: UInt64,
        lastHash: UInt64,
        fileSize: Int64
    ) -> Data {
        var data = Data(capacity: 32)
        withUnsafeBytes(of: firstHash.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: middleHash.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: lastHash.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: fileSize.bigEndian) { data.append(contentsOf: $0) }
        return data
    }
}
