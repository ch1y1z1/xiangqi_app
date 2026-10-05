import Foundation
import Security

enum DeepSeekKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.chiyizi.xiangqi") + ".deepseek",
         kSecAttrAccount as String: "api-key"]
    }

    static func load() throws -> String {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw error(status, action: "读取")
        }
        return key
    }

    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status, action: "删除") }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw error(added, action: "保存") }
        } else if status != errSecSuccess { throw error(status, action: "保存") }
    }

    private static func error(_ status: OSStatus, action: String) -> NSError {
        NSError(domain: "DeepSeekKeychain", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "无法\(action)密钥（\(status)），请重试。"])
    }
}
