import Foundation
import Security

protocol ShareFloatPreferenceStore {
    var oneTapFloat: Bool { get }
    @discardableResult func setOneTapFloat(_ enabled: Bool) -> Bool
}

/// A single non-secret preference shared only by Cod and CodShare. Personal
/// profiles allow this narrowly scoped keychain group without an App Group.
/// No clipboard transport: copying something else must not reset the switch.
final class SharePreferences: ShareFloatPreferenceStore {
    static let shared = SharePreferences()

    private let accessGroup: String?
    private let service: String
    private let account: String

    init(
        accessGroup: String? = Bundle.main.object(forInfoDictionaryKey: "CodShareSettingsAccessGroup") as? String,
        service: String = "com.josh.cod.share-preferences",
        account: String = SharePreferences.defaultAccount
    ) {
        self.accessGroup = accessGroup
        self.service = service
        self.account = account
    }

    static var defaultAccount: String {
        #if COD_PERSONAL
        return "oneTapFloat"
        #else
        return "quickFloatWholeImage"
        #endif
    }

    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    var oneTapFloat: Bool {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { CodDiagnosticLog.record("share preference read failed status=\(status)") }
            #if COD_PERSONAL
            return false
            #else
            return true
            #endif
        }
        return Self.decode(result as? Data)
    }

    static func decode(_ data: Data?) -> Bool { data == Data([1]) }

    @discardableResult
    func setOneTapFloat(_ enabled: Bool) -> Bool {
        let data = Data([enabled ? 1 : 0])
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        CodDiagnosticLog.record("share preference write oneTapFloat=\(enabled) status=\(status)")
        return status == errSecSuccess
    }
}
