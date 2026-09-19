import Foundation
import Security

public protocol TypeSafeAPIKeyStoring: Sendable {
    func load() throws -> String?
    func save(_ value: String) throws
    func remove() throws
}

public enum TypeSafeAPIKeyStoreError: LocalizedError, Sendable, Equatable {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Could not access the TypeSafe API key in Keychain (status \(status))."
        }
    }
}

public struct TypeSafeAPIKeyStore: TypeSafeAPIKeyStoring, Sendable {
    public static let shared = TypeSafeAPIKeyStore()

    private let service: String
    private let account: String

    public init(
        service: String = "com.pywalpick.typesafe",
        account: String = "api-key"
    ) {
        self.service = service
        self.account = account
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw TypeSafeAPIKeyStoreError.keychain(errSecInternalError)
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw TypeSafeAPIKeyStoreError.keychain(status)
        }
    }

    public func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try remove()
            return
        }

        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw TypeSafeAPIKeyStoreError.keychain(status)
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TypeSafeAPIKeyStoreError.keychain(addStatus)
        }
    }

    public func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TypeSafeAPIKeyStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
