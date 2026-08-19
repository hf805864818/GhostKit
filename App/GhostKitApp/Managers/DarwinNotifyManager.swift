//
//  DarwinNotifyManager.swift
//  GhostKit
//
//  App-side Darwin notification manager.
//  Sends cross-process notifications to the Tweak layer (injected into
//  target apps).  Since Darwin notifications cannot carry userInfo,
//  command parameters are written to a shared plist file before
//  posting the notification, and results are read back from another
//  shared file after the Tweak processes the command.
//

import Foundation

/// Shared file paths (must match the Tweak's Tweak.x constants).
private let kGhostKitDir      = "/var/mobile/Library/GhostKit"
private let kCommandFilePath  = "/var/mobile/Library/GhostKit/command.plist"
private let kResultFilePath   = "/var/mobile/Library/GhostKit/result.plist"

/// Darwin notification name constants (must match the Tweak's Tweak.x constants).
public enum DarwinCommand: String {
    // Keychain
    case cleanKeychain         = "GhostKitCleanKeychain"
    case deepCleanKeychain     = "GhostKitDeepCleanKeychain"
    case deleteAllKeychains    = "GhostKitDeleteAllKeychains"
    case backupKeychain        = "GhostKitBackupKeychain"
    case restoreKeychain       = "GhostKitRestoreKeychain"
    case listKeychain          = "GhostKitListKeychain"

    // Identifier
    case refreshIDFA           = "GhostKitRefreshIDFA"
    case changeIdentifier      = "GhostKitChangeIdentifier"
    case getCurrentIdentifiers = "GhostKitGetCurrentIdentifiers"

    // Device reset
    case resetDevice           = "GhostKitResetDevice"
    case getDeviceInfo         = "GhostKitGetDeviceInfo"

    // Cache cleaner
    case cleanSystemResidue    = "GhostKitCleanSystemResidue"
    case cleanDatabaseCache    = "GhostKitCleanDatabaseCache"
    case cleanDataDirectory    = "GhostKitCleanDataDirectory"
    case cleanCookies          = "GhostKitCleanCookies"
    case cleanPasteboard       = "GhostKitCleanPasteboard"
    case getAppSize            = "GhostKitGetAppSize"

    // App list
    case getAllApps            = "GhostKitGetAllApps"
    case searchApps            = "GhostKitSearchApps"
    case uninstallApp          = "GhostKitUninstallApp"
    case getAppInfo            = "GhostKitGetAppInfo"

    // Account
    case getAccountList        = "GhostKitGetAccountList"
    case addAccount            = "GhostKitAddAccount"
    case deleteAccount         = "GhostKitDeleteAccount"
    case getCurrentAccount    = "GhostKitGetCurrentAccount"
    case switchAccount         = "GhostKitSwitchAccount"

    // Permission
    case allowPasteForAll      = "GhostKitAllowPasteForAll"
    case isPasteAllowed        = "GhostKitIsPasteAllowed"

    // System
    case safeExit              = "GhostKitSafeExit"
    case respring              = "GhostKitRespring"
    case ldrestart             = "GhostKitLdrestart"

    // Injection
    case injectDylib           = "GhostKitInjectDylib"
    case removeDylib           = "GhostKitRemoveDylib"
    case getInjectedDylibs     = "GhostKitGetInjectedDylibs"

    // Graphics
    case applyGraphicsConfig   = "GhostKitApplyGraphicsConfig"
    case getAvailablePresets   = "GhostKitGetAvailablePresets"
    case getCurrentGraphics    = "GhostKitGetCurrentGraphics"
    case restoreDefaultGraphics = "GhostKitRestoreDefaultGraphics"
}

public class DarwinNotifyManager {

    public static let shared = DarwinNotifyManager()

    private let fm = FileManager.default

    private init() {
        // Ensure the shared directory exists.
        try? fm.createDirectory(atPath: kGhostKitDir,
                                withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Send a Darwin command to the Tweak layer with optional parameters.
    /// Blocks until the Tweak writes a result file or times out.
    ///
    /// - Parameters:
    ///   - command: The Darwin command to send.
    ///   - params: Optional parameters dictionary (e.g., ["bundleID": "com.example.app"]).
    ///   - timeout: Maximum seconds to wait for a result (default 10s).
    /// - Returns: The result dictionary from the Tweak, or nil on timeout.
    public func sendCommand(_ command: DarwinCommand,
                            params: [String: Any]? = nil,
                            timeout: TimeInterval = 10.0) -> [String: Any]? {

        // 1. Remove any stale result file.
        removeResultFile()

        // 2. Write command parameters to the shared file.
        var commandDict: [String: Any] = ["command": command.rawValue]
        if let params = params {
            commandDict["params"] = params
        }
        let success = (commandDict as NSDictionary).write(toFile: kCommandFilePath, atomically: true)
        guard success else {
            NSLog("[GhostKit] DarwinNotify: failed to write command file")
            return nil
        }

        // 3. Post the Darwin notification.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = command.rawValue as CFString
        CFNotificationCenterPostNotification(center, CFNotificationName(name), nil, nil, true)

        // 4. Poll for the result file.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = readResultFile() {
                // Verify this result is for our command.
                if let cmd = result["command"] as? String,
                   cmd == command.rawValue {
                    return result
                }
            }
            usleep(50_000)  // 50ms between polls
        }

        NSLog("[GhostKit] DarwinNotify: timeout waiting for result for %@", command.rawValue)
        return nil
    }

    /// Send a fire-and-forget Darwin command (no result expected).
    /// Used for commands like respring/ldrestart that may kill the process.
    public func sendFireAndForget(_ command: DarwinCommand,
                                 params: [String: Any]? = nil) {
        // Write command parameters.
        var commandDict: [String: Any] = ["command": command.rawValue]
        if let params = params {
            commandDict["params"] = params
        }
        (commandDict as NSDictionary).write(toFile: kCommandFilePath, atomically: true)

        // Post the Darwin notification.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = command.rawValue as CFString
        CFNotificationCenterPostNotification(center, CFNotificationName(name), nil, nil, true)
    }

    // MARK: - Private helpers

    private func removeResultFile() {
        try? fm.removeItem(atPath: kResultFilePath)
    }

    private func readResultFile() -> [String: Any]? {
        guard fm.fileExists(atPath: kResultFilePath) else {
            return nil
        }
        return NSDictionary(contentsOfFile: kResultFilePath) as? [String: Any]
    }

    // MARK: - Convenience methods

    /// Send a command that operates on a specific bundle ID.
    public func sendBundleIDCommand(_ command: DarwinCommand,
                                    bundleID: String,
                                    timeout: TimeInterval = 10.0) -> Bool {
        let result = sendCommand(command, params: ["bundleID": bundleID], timeout: timeout)
        if let res = result?["result"] as? Bool {
            return res
        }
        if let res = result?["result"] as? Int {
            return res != 0
        }
        return false
    }

    /// Send a command that returns a dictionary result.
    public func sendDictionaryCommand(_ command: DarwinCommand,
                                      bundleID: String? = nil,
                                      timeout: TimeInterval = 10.0) -> [String: Any] {
        var params: [String: Any] = [:]
        if let bid = bundleID { params["bundleID"] = bid }
        let result = sendCommand(command, params: params.isEmpty ? nil : params, timeout: timeout)
        return (result?["result"] as? [String: Any]) ?? [:]
    }

    /// Send a command that returns an array result.
    public func sendArrayCommand(_ command: DarwinCommand,
                                  bundleID: String? = nil,
                                  timeout: TimeInterval = 10.0) -> [[String: Any]] {
        var params: [String: Any] = [:]
        if let bid = bundleID { params["bundleID"] = bid }
        let result = sendCommand(command, params: params.isEmpty ? nil : params, timeout: timeout)
        return (result?["result"] as? [[String: Any]]) ?? []
    }

    /// Send a command that returns a string result.
    public func sendStringCommand(_ command: DarwinCommand,
                                   bundleID: String? = nil,
                                   timeout: TimeInterval = 10.0) -> String {
        var params: [String: Any] = [:]
        if let bid = bundleID { params["bundleID"] = bid }
        let result = sendCommand(command, params: params.isEmpty ? nil : params, timeout: timeout)
        return (result?["result"] as? String) ?? ""
    }
}
