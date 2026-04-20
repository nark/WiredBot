import Foundation

#if canImport(Security)
import Security
#else
public typealias OSStatus = Int32
#endif

public enum ServerPasswordKeychain {
    public static let defaultService = "fr.read-write.wiredbot.server"

    public static func service(for server: ServerConfig) -> String {
        let trimmed = server.keychainService?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : defaultService
    }

    public static func account(for server: ServerConfig) -> String {
        let explicit = server.keychainAccount?.trimmingCharacters(in: .whitespacesAndNewlines)
        if explicit?.isEmpty == false {
            return explicit!
        }

        guard let components = URLComponents(string: server.url) else {
            return "guest@localhost:4871"
        }

        let user = components.user?.isEmpty == false ? components.user! : "guest"
        let host = components.host?.isEmpty == false ? components.host! : "localhost"
        let port = components.port ?? 4871
        return "\(user)@\(host):\(port)"
    }

    public static func sanitizedURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }
        components.password = nil
        return components.string ?? urlString
    }

    public static func urlByInjecting(password: String, into urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }
        components.password = password
        return components.string ?? urlString
    }

    public static func readPassword(service: String, account: String) throws -> String? {
        #if canImport(Security)
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    public static func savePassword(_ password: String, service: String, account: String) throws {
        #if canImport(Security)
        let data = Data(password.utf8)
        var query = baseQuery(service: service, account: account)

        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(addStatus)
        }
        #else
        throw KeychainError.unsupportedPlatform
        #endif
    }

    public static func deletePassword(service: String, account: String) throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
        #else
        throw KeychainError.unsupportedPlatform
        #endif
    }

    #if canImport(Security)
    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    #endif
}

public enum KeychainError: LocalizedError {
    case unsupportedPlatform
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Keychain is only available on macOS."
        case .unhandledStatus(let status):
            return "Keychain error \(status)."
        }
    }
}
