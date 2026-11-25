import Foundation
import Security
import LocalAuthentication
import SwiftUI

enum Keychain {
    private static let service = "app.veltrix.simulation"
    enum Failure: Error { case storage }

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    static func exists(_ key: String) throws -> Bool {
        let status = SecItemCopyMatching(query(key) as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw Failure.storage }
        return true
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
    typealias Evaluator = @MainActor (LAPolicy) async throws -> Bool

    @Published private(set) var enabled = false
    @Published private(set) var locked = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?

    private let defaults: UserDefaults
    private let legacyLock: () throws -> Bool
    private let evaluator: Evaluator?
    private var context: LAContext?
    private var backgrounded: Date?
    private var attemptedAutomatically = false
    private var generation = 0

    init(defaults: UserDefaults = .standard, testing: Bool = false,
         legacyLock: (() throws -> Bool)? = nil, evaluator: Evaluator? = nil) {
        self.defaults = defaults
        self.evaluator = evaluator
        self.legacyLock = legacyLock ?? { !testing ? try Keychain.exists("pin") : false }

        if let saved = defaults.object(forKey: "deviceLockEnabled") as? Bool {
            enabled = saved
        } else {
            do {
                enabled = try defaults.bool(forKey: "biometrics") || self.legacyLock()
                defaults.set(enabled, forKey: "deviceLockEnabled")
            } catch {
                // Keep the app locked until iOS authorizes access if the legacy setting cannot be read.
                enabled = true
            }
        }
        locked = enabled
    }

    var timeout: Int { defaults.object(forKey: "lockTimeout") as? Int ?? 60 }

    func setTimeout(_ seconds: Int) {
        defaults.set(seconds, forKey: "lockTimeout")
        objectWillChange.send()
    }

    func setEnabled(_ value: Bool) async {
        guard enabled != value, !locked, await authenticate() else { return }
        enabled = value
        defaults.set(value, forKey: "deviceLockEnabled")
    }

    func enteredBackground(at date: Date = .now) {
        backgrounded = date
        generation += 1
        context?.invalidate()
        if timeout == 0 { lockNow() }
        if locked { attemptedAutomatically = false }
    }

    func becomeActive(at date: Date = .now) {
        if let backgrounded, date.timeIntervalSince(backgrounded) >= Double(timeout) { lockNow() }
        backgrounded = nil
    }

    func lockNow() {
        guard enabled, !locked else { return }
        generation += 1
        attemptedAutomatically = false
        error = nil
        locked = true
    }

    func tryAutomaticUnlock() async {
        guard enabled, locked, !attemptedAutomatically, !busy else { return }
        attemptedAutomatically = true
        await unlockWithDevice()
    }

    func unlockWithDevice() async {
        guard enabled, locked, await authenticate() else { return }
        locked = false
        Feedback.success()
    }

    private func authenticate() async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        let attempt = generation
        defer { busy = false; context = nil }

        do {
            let policy = LAPolicy.deviceOwnerAuthentication
            let success: Bool
            if let evaluator {
                success = try await evaluator(policy)
            } else {
                let native = LAContext()
                context = native
                var unavailable: NSError?
                guard native.canEvaluatePolicy(policy, error: &unavailable) else {
                    if let unavailable { throw unavailable }
                    error = L.text("Device authentication unavailable")
                    return false
                }
                success = try await native.evaluatePolicy(policy, localizedReason: L.text("Protect your portfolio"))
            }
            return success && generation == attempt
        } catch {
            guard generation == attempt else { return false }
            let code = (error as? LAError)?.code
            if code == .passcodeNotSet {
                self.error = L.text("Set a device passcode in iOS Settings to unlock Veltrix.")
            } else if code != .userCancel && code != .systemCancel && code != .appCancel {
                self.error = L.text("Device authentication was unsuccessful")
            }
            return false
        }
    }
}
