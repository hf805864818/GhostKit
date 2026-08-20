//
//  detectSystemAppleID_fix.swift
//  替代原 AccountListView.swift 中的 detectSystemAppleID()
//  修复 iOS 16+ Apple ID 检测
//

import Foundation
import Security

func detectSystemAppleID_fixed() -> String? {
    // === 方法1：用正确的 iOS 16+ Keychain 查询 ===
    // iOS 16+ 的 Apple ID token 存储在以下 access group 下：
    // com.apple.account.AppleID.<bundleID>
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: "com.apple.account.AppleID.",
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnAttributes as String: true,
    ]
    var result: AnyObject?
    if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
       let dict = result as? [String: Any],
       let acct = dict[kSecAttrAccount as String] as? String,
       !acct.isEmpty {
        // 提取 Apple ID（格式: com.apple.account.AppleID.<realID>）
        if acct.hasPrefix("com.apple.account.AppleID.") {
            return String(acct.dropFirst("com.apple.account.AppleID.".count))
        }
        return acct
    }

    // === 方法2：查询 iTunes Store 相关 Keychain 条目 ===
    let itunesQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.apple.iTunesStore",
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnAttributes as String: true,
    ]
    var itunesResult: AnyObject?
    if SecItemCopyMatching(itunesQuery as CFDictionary, &itunesResult) == errSecSuccess,
       let dict = itunesResult as? [String: Any],
       let acct = dict[kSecAttrAccount as String] as? String,
       !acct.isEmpty {
        return acct
    }

    // === 方法3：查询 com.apple.application-identifier ===
    let appIDQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.apple.application-identifier",
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnAttributes as String: true,
    ]
    var appIDResult: AnyObject?
    if SecItemCopyMatching(appIDQuery as CFDictionary, &appIDResult) == errSecSuccess,
       let dict = appIDResult as? [String: Any],
       let acct = dict[kSecAttrAccount as String] as? String,
       !acct.isEmpty {
        return acct
    }

    // === 方法4：检查 AppStore plist（iOS 15 及以下） ===
    let appStorePrefsPath = "/var/mobile/Library/Preferences/com.apple.AppStore.plist"
    if let dict = NSDictionary(contentsOfFile: appStorePrefsPath) {
        if let appleID = dict["AppleID"] as? String, !appleID.isEmpty {
            return appleID
        }
        if let signedIn = dict["SignedInAppleID"] as? String, !signedIn.isEmpty {
            return signedIn
        }
    }

    // === 方法5：MobileMeAccounts（iCloud 账号，可能 ≠ App Store 账号）===
    let mobileMePath = "/var/mobile/Library/Preferences/MobileMeAccounts.plist"
    if let dict = NSDictionary(contentsOfFile: mobileMePath) {
        if let accounts = dict["Accounts"] as? [[String: Any]] {
            for acc in accounts {
                if let id = acc["AccountID"] as? String, !id.isEmpty {
                    return id
                }
            }
        }
    }

    return nil
}
