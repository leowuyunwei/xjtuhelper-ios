//
//  SecretStore.swift
//  XJTUBox
//
//  钥匙串封装：密码、Cookie 快照、AI API Key 都进 Keychain，不写进 UserDefaults。
//

import Foundation
import Security

enum SecretStore {
    private static let service = "com.xjtu.toolbox.ios.secrets"

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func removeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 非敏感偏好设置，直接放 UserDefaults。
enum Prefs {
    private static let defaults = UserDefaults.standard

    static var savedAccounts: [String] {
        get { defaults.stringArray(forKey: "savedAccounts") ?? [] }
        set { defaults.set(newValue, forKey: "savedAccounts") }
    }

    static var activeAccount: String? {
        get { defaults.string(forKey: "activeAccount") }
        set { defaults.set(newValue, forKey: "activeAccount") }
    }

    static var agentBaseURL: String {
        get { defaults.string(forKey: "agentBaseURL") ?? "https://api.deepseek.com/v1" }
        set { defaults.set(newValue, forKey: "agentBaseURL") }
    }

    static var agentModel: String {
        get { defaults.string(forKey: "agentModel") ?? "deepseek-chat" }
        set { defaults.set(newValue, forKey: "agentModel") }
    }

    static var agentSystemPrompt: String {
        get { defaults.string(forKey: "agentSystemPrompt") ?? AgentDefaults.systemPrompt }
        set { defaults.set(newValue, forKey: "agentSystemPrompt") }
    }

    static var colorSchemePreference: String {
        get { defaults.string(forKey: "colorSchemePreference") ?? "system" }
        set { defaults.set(newValue, forKey: "colorSchemePreference") }
    }
}

enum AgentDefaults {
    static let systemPrompt = """
    你是西安交通大学学生的校园助手「屁岱」。回答简洁、口语化，涉及课程、成绩、校园卡等数据时\
    优先使用调用方提供的上下文，不要编造学校系统的数据。不确定的信息要说明来源或让用户去学校系统确认。
    """
}
