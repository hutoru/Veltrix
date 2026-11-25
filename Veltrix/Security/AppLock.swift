import Foundation
import Security
import CommonCrypto
import LocalAuthentication
import SwiftUI

enum Keychain {
    private static let service = "app.veltrix.simulation"
    enum Failure: Error { case storage }

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    static func read(_ key: String) throws -> Data? {
        var request = query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.storage }
        return data
    }

    static func write(_ data: Data, key: String) throws {
        let request = query(key)
        let fields: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(request as CFDictionary, fields as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.storage }
        let attributes = request.merging(fields) { _, new in new }.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]) { _, new in new }
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw Failure.storage }
    }

    static func remove(_ key: String) throws {
        let result = SecItemDelete(query(key) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw Failure.storage }
    }
}

@MainActor final class AppLock: ObservableObject {
    @Published private(set) var locked = false
    @Published private(set) var hasPIN = false
    @Published private(set) var retryAt: Date?
    @Published private(set) var busy = false
    @Published var error: String?

    private struct Record: Codable {
        var salt: Data
        var hash: Data
        var attempts: Int = 0
        var retryAt: Date?
    }
    private var record: Record?
    private var backgrounded: Date?
    private let defaults: UserDefaults
    private let testing: Bool
    private var keychainUnavailable = false

    init(defaults: UserDefaults = .standard, testing: Bool = false) {
        self.defaults = defaults
        self.testing = testing
        readRecord()
        locked = hasPIN || biometrics || keychainUnavailable
    }

    private func readRecord() {
        if testing { return }
        do {
            record = try Keychain.read("pin").map { try JSONDecoder().decode(Record.self, from: $0) }
            hasPIN = record != nil
            retryAt = record?.retryAt
            keychainUnavailable = false
        } catch {
            keychainUnavailable = true
            self.error = L.text("Secure storage unavailable")
        }
    }

    var biometrics: Bool { defaults.bool(forKey: "biometrics") }
    var timeout: Int { defaults.object(forKey: "lockTimeout") as? Int ?? 60 }

    func setTimeout(_ seconds: Int) {
        defaults.set(seconds, forKey: "lockTimeout")
        objectWillChange.send()
    }

    func changeBiometrics(_ enabled: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if await authenticateDevice(biometricOnly: enabled) {
            defaults.set(enabled, forKey: "biometrics")
            objectWillChange.send()
        }
    }

    func enteredBackground() {
        backgrounded = Date()
        if (hasPIN || biometrics) && timeout == 0 { locked = true }
    }

    func becomeActive() {
        if keychainUnavailable {
            readRecord()
            if !keychainUnavailable && !hasPIN && !biometrics { locked = false }
        }
        if (hasPIN || biometrics), let backgrounded, Date().timeIntervalSince(backgrounded) >= Double(timeout) {
            locked = true
        }
        backgrounded = nil
    }

    func lockNow() {
        if hasPIN || biometrics { locked = true }
    }

    func unlockWithDevice() async {
        guard !busy, biometrics, !keychainUnavailable else { return }
        busy = true
        defer { busy = false }
        if await authenticateDevice(biometricOnly: hasPIN) {
            locked = false
            error = nil
        }
    }

    func unlock(pin: String) async {
        guard !busy, let record, !keychainUnavailable else { return }
        busy = true
        defer { busy = false }
        guard retryAt.map({ $0 <= Date() }) ?? true else {
            error = L.text("Try again after the displayed time.")
            return
        }
        do {
            guard Self.valid(pin) else { throw Keychain.Failure.storage }
            let candidate = try await derive(pin, salt: record.salt)
            var next = record
            if Self.matches(record.hash, candidate) {
                next.attempts = 0
                next.retryAt = nil
                try save(next)
                locked = false
                error = nil
            } else {
                next.attempts = min(record.attempts + 1, 16)
                if next.attempts >= 5 {
                    next.retryAt = Date().addingTimeInterval(Double(min(3_600, 15 << (next.attempts - 5))))
                }
                try save(next)
                error = L.text("Incorrect PIN")
            }
        } catch {
            self.error = L.text("PIN or secure storage error")
        }
    }

    func updatePIN(current: String, new: String?) async -> Bool {
        guard !busy, !keychainUnavailable else { return false }
        busy = true
        defer { busy = false }
        do {
            if let record {
                guard retryAt.map({ $0 <= Date() }) ?? true else {
                    error = L.text("Try again after the displayed time.")
                    return false
                }
                guard Self.valid(current) else {
                    error = L.text("Use 4–8 digits.")
                    return false
                }
                let derived = try await derive(current, salt: record.salt)
                guard Self.matches(record.hash, derived) else {
                    var failed = record
                    failed.attempts = min(failed.attempts + 1, 16)
                    if failed.attempts >= 5 {
                        failed.retryAt = Date().addingTimeInterval(Double(min(3_600, 15 << (failed.attempts - 5))))
                    }
                    try save(failed)
                    error = L.text("Incorrect PIN")
                    return false
                }
            }
            if let new {
                guard Self.valid(new) else { error = L.text("Use 4–8 digits."); return false }
                var random = [UInt8](repeating: 0, count: 32)
                let status = random.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
                guard status == errSecSuccess else { throw Keychain.Failure.storage }
                let salt = Data(random)
                let hash = try await derive(new, salt: salt)
                try save(Record(salt: salt, hash: hash))
            } else {
                if !testing { try Keychain.remove("pin") }
                record = nil
                hasPIN = false
                retryAt = nil
            }
            error = nil
            return true
        } catch {
            self.error = L.text("Secure storage unavailable")
            return false
        }
    }

    private func authenticateDevice(biometricOnly: Bool) async -> Bool {
        let context = LAContext()
        let policy: LAPolicy = biometricOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: nil) else {
            error = L.text("Device authentication unavailable")
            return false
        }
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: L.text("Protect your portfolio"))
            if success { error = nil }
            return success
        } catch {
            self.error = L.text("Device authentication was unsuccessful")
            return false
        }
    }

    private func save(_ record: Record) throws {
        if !testing { try Keychain.write(JSONEncoder().encode(record), key: "pin") }
        self.record = record
        hasPIN = true
        retryAt = record.retryAt
    }

    private func derive(_ pin: String, salt: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let password = Array(pin.utf8)
            var hash = Data(count: 32)
            let status = hash.withUnsafeMutableBytes { hashBytes in
                password.withUnsafeBytes { passwordBytes in
                    salt.withUnsafeBytes { saltBytes in
                        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.bindMemory(to: Int8.self).baseAddress,
                                             passwordBytes.count, saltBytes.bindMemory(to: UInt8.self).baseAddress,
                                             saltBytes.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 210_000,
                                             hashBytes.bindMemory(to: UInt8.self).baseAddress, hashBytes.count)
                    }
                }
            }
            guard status == kCCSuccess else { throw Keychain.Failure.storage }
            return hash
        }.value
    }

    private static func valid(_ pin: String) -> Bool {
        (4...8).contains(pin.utf8.count) && pin.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func matches(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
