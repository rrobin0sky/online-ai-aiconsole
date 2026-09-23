import Foundation
import Security
import CryptoKit

public final class KeychainHelper: @unchecked Sendable {
    public static let shared = KeychainHelper()
    
    private let serviceName = "com.robin.AIConsole.credentials"
    private var memoryCache: [String: String] = [:]
    private let lock = NSLock()
    
    private init() {
        migrateLegacyVaultIfNeeded()
    }
    
    /// Migrates credentials from legacy AES-GCM file to Apple Keychain
    private func migrateLegacyVaultIfNeeded() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let appDir = appSupport.appendingPathComponent("AIConsole", isDirectory: true)
        let vaultURL = appDir.appendingPathComponent(".secure_vault.dat")
        let saltURL = appDir.appendingPathComponent(".salt")
        
        guard FileManager.default.fileExists(atPath: vaultURL.path),
              let saltData = try? String(contentsOf: saltURL, encoding: .utf8),
              let encryptedData = try? Data(contentsOf: vaultURL) else { return }
        
        let keyData = SHA256.hash(data: saltData.data(using: .utf8) ?? Data())
        let symmetricKey = SymmetricKey(data: keyData)
        
        if let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
           let decryptedData = try? AES.GCM.open(sealedBox, using: symmetricKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: decryptedData) {
            for (k, v) in dict {
                saveToKeychain(key: k, secret: v)
            }
            // Securely clean up legacy vault and salt file after successful migration
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: saltURL)
        }
    }
    
    // MARK: - Keychain Core Operations
    
    @discardableResult
    public func save(key: String, secret: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        memoryCache[key] = secret
        return saveToKeychain(key: key, secret: secret)
    }
    
    public func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = memoryCache[key] {
            return cached
        }
        
        if let fromKeychain = readFromKeychain(key: key) {
            memoryCache[key] = fromKeychain
            return fromKeychain
        }
        return nil
    }
    
    @discardableResult
    public func delete(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        memoryCache.removeValue(forKey: key)
        return deleteFromKeychain(key: key)
    }
    
    // MARK: - Native Apple Security Framework Primitives
    
    @discardableResult
    private func saveToKeychain(key: String, secret: String) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        // Delete existing if present
        SecItemDelete(query as CFDictionary)
        
        var newAttributes = query
        newAttributes[kSecValueData as String] = data
        newAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        
        let status = SecItemAdd(newAttributes as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func readFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
    
    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
