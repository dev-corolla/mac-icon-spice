import Foundation
import Security

/// The API key lives only in the user's Keychain. This store never persists it in app settings.
public struct KeychainStore: Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.iconspice.openai", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    /// Checks saved-key presence without requesting or decrypting its secret value.
    public func hasAPIKey() throws -> Bool {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError.operation(status) }
        return true
    }

    public func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyKey }
        let data = Data(trimmed.utf8)
        let update = [kSecValueData: data] as CFDictionary
        let status = SecItemUpdate(query, update)
        if status == errSecItemNotFound {
            let attributes: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData: data
            ]
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.operation(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.operation(status)
        }
    }

    public func apiKey() throws -> String? {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.operation(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return key
    }

    public func deleteAPIKey() throws {
        let status = SecItemDelete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operation(status)
        }
    }

    private var query: CFDictionary {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
    }
}

public enum KeychainError: Error, Sendable, LocalizedError, Equatable {
    case emptyKey
    case invalidData
    case operation(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyKey: "Enter an API key before saving."
        case .invalidData: "The saved API key could not be read. Save it again in Settings."
        case .operation(let status): "Keychain access failed (\(status))."
        }
    }
}
