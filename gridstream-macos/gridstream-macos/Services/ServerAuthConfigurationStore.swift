import Foundation
import OSLog
import Security
import Vapor

nonisolated struct ServerAuthConfiguration: Codable, Sendable {
    var isEnabled: Bool
    var pinHash: String?
    var pinRevision: Int
    var sessionTTLDays: Int
    var tokenSecret: String
    /// Plaintext of the PIN generated on first launch, kept only so the menu bar
    /// and Settings can show it. Cleared as soon as the user sets their own PIN.
    var generatedPIN: String? = nil

    static let defaultSessionTTLDays = 30

    var hasPIN: Bool {
        guard let pinHash else { return false }
        return !pinHash.isEmpty
    }

    var requiresAuthentication: Bool {
        isEnabled && hasPIN
    }

    static func `default`() -> ServerAuthConfiguration {
        ServerAuthConfiguration(
            isEnabled: false,
            pinHash: nil,
            pinRevision: 0,
            sessionTTLDays: defaultSessionTTLDays,
            tokenSecret: UUID().uuidString
        )
    }
}

// MARK: - Sendable Justification
//
// `ServerAuthConfigurationStore` is `@unchecked Sendable` because all access
// to the underlying `UserDefaults` instance and secret store (each per-key
// thread-safe but not atomic across keys) is serialized through `lock`.
// Without the lock, a concurrent Vapor handler reading the configuration
// during a save could observe a torn snapshot — e.g. the new `pinHash` paired
// with the old `pinRevision`, invalidating bearer tokens minted seconds earlier.
nonisolated final class ServerAuthConfigurationStore: @unchecked Sendable {
    private enum Keys {
        static let authEnabled = "serverAuthEnabled"
        static let pinHash = "serverPinHash"
        static let pinRevision = "serverPinRevision"
        static let sessionTTLDays = "serverSessionTTLDays"
        static let tokenSecret = "serverAuthTokenSecret"
        static let generatedPIN = "serverGeneratedPIN"
        static let revokedTokenIds = "serverRevokedTokenIds"

        /// Kept in `secrets`, never in `UserDefaults`.
        static let secrets = [tokenSecret, pinHash, generatedPIN]
    }

    static let shared = ServerAuthConfigurationStore(defaults: .standard, secrets: KeychainSecretStore())

    private let defaults: UserDefaults
    private let secrets: SecretStore
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "ServerAuthConfigurationStore")

    /// `secrets` holds the token secret, PIN hash and generated PIN. Tests pass
    /// an `InMemorySecretStore` or a `KeychainSecretStore` with their own service.
    nonisolated init(defaults: UserDefaults, secrets: SecretStore) {
        self.defaults = defaults
        self.secrets = secrets
        lock.withLock {
            migrateSecretsFromDefaultsLocked()
            ensureSecretExistsLocked()
        }
    }

    nonisolated func load() -> ServerAuthConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return ServerAuthConfiguration(
            isEnabled: defaults.bool(forKey: Keys.authEnabled),
            pinHash: secretLocked(Keys.pinHash),
            pinRevision: defaults.integer(forKey: Keys.pinRevision),
            sessionTTLDays: sessionTTLDaysValueLocked(),
            tokenSecret: tokenSecretValueLocked(),
            generatedPIN: secretLocked(Keys.generatedPIN)
        )
    }

    nonisolated func save(_ configuration: ServerAuthConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        defaults.set(configuration.isEnabled, forKey: Keys.authEnabled)
        setSecretLocked(configuration.pinHash, forKey: Keys.pinHash)
        defaults.set(configuration.pinRevision, forKey: Keys.pinRevision)
        defaults.set(configuration.sessionTTLDays, forKey: Keys.sessionTTLDays)
        setSecretLocked(configuration.tokenSecret, forKey: Keys.tokenSecret)
        setSecretLocked(configuration.generatedPIN, forKey: Keys.generatedPIN)
    }

    /// Auth is on by default: when no PIN exists (first launch, or upgrade from
    /// a version where auth was off by default), generates a random 6-digit
    /// PIN and enables auth. Returns the generated PIN, nil if one already existed.
    @discardableResult
    nonisolated func ensureDefaultPIN() throws -> String? {
        guard !load().hasPIN else { return nil }

        let pin = ServerPINSecurity.generatePIN()
        let hash = try ServerPINSecurity.hash(pin: pin)

        lock.lock()
        defer { lock.unlock() }
        // Re-check under the lock: another caller may have set a PIN meanwhile
        if let existing = secretLocked(Keys.pinHash), !existing.isEmpty {
            return nil
        }
        setSecretLocked(hash, forKey: Keys.pinHash)
        defaults.set(true, forKey: Keys.authEnabled)
        setSecretLocked(pin, forKey: Keys.generatedPIN)
        return pin
    }

    /// A new token signing secret: 32 random bytes, base64-encoded.
    nonisolated static func generateTokenSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Revoked token ids (logout)

    /// Records a logged-out token id until its expiry; expired entries are pruned.
    nonisolated func revokeTokenId(_ tokenId: String, expiresAt: TimeInterval, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var revoked = revokedTokenIdsLocked().filter { $0.value > now.timeIntervalSince1970 }
        revoked[tokenId] = expiresAt
        defaults.set(revoked, forKey: Keys.revokedTokenIds)
    }

    nonisolated func isTokenIdRevoked(_ tokenId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return revokedTokenIdsLocked()[tokenId] != nil
    }

    // Precondition: caller holds `lock`.
    private nonisolated func revokedTokenIdsLocked() -> [String: Double] {
        (defaults.dictionary(forKey: Keys.revokedTokenIds) as? [String: Double]) ?? [:]
    }

    // MARK: - Secrets

    /// Moves secrets written by earlier versions from `UserDefaults` into the
    /// secret store, unchanged, so tokens signed with the old secret stay
    /// valid. A value already in the secret store wins. A defaults key is only
    /// removed once its value is safely stored.
    // Precondition: caller holds `lock`.
    private nonisolated func migrateSecretsFromDefaultsLocked() {
        for key in Keys.secrets {
            guard let legacy = defaults.string(forKey: key) else { continue }
            do {
                if try secrets.string(forKey: key) == nil {
                    try secrets.setString(legacy, forKey: key)
                }
                defaults.removeObject(forKey: key)
            } catch {
                logger.error("Could not move \(key, privacy: .public) to the Keychain: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Precondition: caller holds `lock`.
    private nonisolated func ensureSecretExistsLocked() {
        if secretLocked(Keys.tokenSecret)?.isEmpty != false {
            setSecretLocked(Self.generateTokenSecret(), forKey: Keys.tokenSecret)
        }
    }

    /// Reads a secret, falling back to a `UserDefaults` value the secret store
    /// could not take yet (Keychain unavailable).
    // Precondition: caller holds `lock`.
    private nonisolated func secretLocked(_ key: String) -> String? {
        do {
            if let value = try secrets.string(forKey: key) {
                return value
            }
        } catch {
            logger.error("Could not read \(key, privacy: .public) from the Keychain: \(error.localizedDescription, privacy: .public)")
        }
        return defaults.string(forKey: key)
    }

    /// Writes a secret (`nil` removes it). When the secret store fails, the
    /// value is kept in `UserDefaults` so auth keeps working; the next launch
    /// moves it into the secret store.
    // Precondition: caller holds `lock`.
    private nonisolated func setSecretLocked(_ value: String?, forKey key: String) {
        do {
            try secrets.setString(value, forKey: key)
            defaults.removeObject(forKey: key)
        } catch {
            logger.error("Could not write \(key, privacy: .public) to the Keychain: \(error.localizedDescription, privacy: .public)")
            defaults.set(value, forKey: key)
        }
    }

    // Precondition: caller holds `lock`.
    private nonisolated func sessionTTLDaysValueLocked() -> Int {
        let value = defaults.integer(forKey: Keys.sessionTTLDays)
        return value > 0 ? value : ServerAuthConfiguration.defaultSessionTTLDays
    }

    // Precondition: caller holds `lock`.
    private nonisolated func tokenSecretValueLocked() -> String {
        if let secret = secretLocked(Keys.tokenSecret), !secret.isEmpty {
            return secret
        }

        let secret = Self.generateTokenSecret()
        setSecretLocked(secret, forKey: Keys.tokenSecret)
        return secret
    }
}

nonisolated enum ServerPINError: LocalizedError {
    case invalidFormat
    case hashingFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return String(localized: "PIN must contain 6 to 12 digits.")
        case .hashingFailed:
            return String(localized: "Unable to save PIN.")
        }
    }
}

nonisolated enum ServerPINSecurity {
    static func normalize(pin: String) -> String {
        pin.filter(\.isNumber)
    }

    /// Length accepted for a new PIN.
    static let newPINLength = 6...12
    /// Length accepted at login: PINs shorter than 6 digits set by older
    /// versions keep working until changed.
    static let acceptedPINLength = 4...12

    /// Whether `pin` is acceptable as a new PIN (6…12 digits).
    static func validate(pin: String) -> Bool {
        isDigits(pin) && newPINLength.contains(pin.count)
    }

    private static func isDigits(_ pin: String) -> Bool {
        !pin.isEmpty && pin.allSatisfy { ("0"..."9").contains($0) }
    }

    /// A random 6-digit PIN.
    static func generatePIN() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0...999_999, using: &generator))
    }

    static func hash(pin: String) throws -> String {
        guard validate(pin: pin) else {
            throw ServerPINError.invalidFormat
        }

        do {
            return try Bcrypt.hash(pin)
        } catch {
            throw ServerPINError.hashingFailed
        }
    }

    static func verify(pin: String, hash: String) -> Bool {
        guard isDigits(pin), acceptedPINLength.contains(pin.count) else { return false }
        return (try? Bcrypt.verify(pin, created: hash)) ?? false
    }
}
