//
//  KeychainStore.swift
//  TagLeafony
//

import Foundation
import Security

// ============================================================================
//  Keychainに文字列を1つ出し入れするだけの薄いラッパー。
//
//  UserDefaultsやJSONファイルと違い、Keychainは暗号化された領域に
//  保存されるため、JWTのような「漏れたら困る」情報はここに置く。
// ============================================================================

enum KeychainStore {

    private static let service = "jp.tagleafony.app"

    /// 値を保存する。同じキーが既にあれば上書きする。
    static func set(_ value: String, for key: String) {
        delete(key)   // 既存があれば消してから入れ直す（SecItemAddは重複キーを許さない）

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    /// 値を取り出す。無ければ nil。
    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    /// 値を削除する（無くてもエラーにしない）。
    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
