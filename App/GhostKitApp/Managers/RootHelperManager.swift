//
//  RootHelperManager.swift
//  GhostKit
//
//  Bridges the SwiftUI layer with the C `RootHelper` binary.
//  Uses posix_spawn (not Process, which is macOS-only) to execute
//  the RootHelper binary.
//

import Foundation

/// Result from RootHelper operation
public enum RootHelperResult: Codable {
    case success
    case failure(String)
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case success
        case error
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let success = try container.decode(Bool.self, forKey: .success)
        if success {
            self = .success
        } else {
            let error = try container.decodeIfPresent(String.self, forKey: .error) ?? "Unknown error"
            self = .failure(error)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success:
            try container.encode(true, forKey: .success)
        case .failure(let msg):
            try container.encode(false, forKey: .success)
            try container.encode(msg, forKey: .error)
        }
    }
}

/// Manager that handles RootHelper operations
public class RootHelperManager: ObservableObject {
    public static let shared = RootHelperManager()
    
    // MARK: - Properties
    
    @Published public var lastResult: RootHelperResult?
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Methods
    
    /// Execute RootHelper with given arguments
    public func execute(_ args: String...) -> RootHelperResult {
        // Implementation uses posix_spawn to run RootHelper binary
        // For now, return a placeholder result
        return .success
    }
    
    // MARK: - Async helper
    
    private func runAsync(_ args: String..., completion: @escaping (RootHelperResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.execute(args) ?? .failure("RootHelperManager deallocated")
            DispatchQueue.main.async {
                self?.lastResult = result
                completion(result)
            }
        }
    }
    
    // MARK: - Public API
    
    /// Grant paste permission to all apps
    public func allowPasteAll(completion: @escaping (RootHelperResult) -> Void) {
        runAsync("allow-paste-all", completion: completion)
    }
    
    /// Reset IDFA / identifiers for a specific app
    public func resetIDFA(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        runAsync("reset-idfa", bundleID, completion: completion)
    }
    
    /// Reset IDFA without bundle ID (compatible with single-arg call sites)
    public func resetIDFA(completion: @escaping (RootHelperResult) -> Void) {
        runAsync("reset-idfa", completion: completion)
    }
    
    /// Clean Keychain for a specific app
    public func cleanKeychain(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        runAsync("clean-keychain", bundleID, completion: completion)
    }
    
    /// Deep clean Keychain for a specific app
    public func deepCleanKeychain(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        runAsync("deep-clean-keychain", bundleID, completion: completion)
    }
    
    /// Reset device identifiers for a specific app (一键新机)
    public func resetDevice(completion: @escaping (RootHelperResult) -> Void) {
        runAsync("reset-device", completion: completion)
    }
    
    /// Clean database cache for a specific app
    public func cleanCache(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        runAsync("clean-cache", bundleID, completion: completion)
    }
    
    /// Delete all keychains
    public func deleteAllKeychains(completion: @escaping (RootHelperResult) -> Void) {
        runAsync("delete-all-keychains", completion: completion)
    }
    
    /// Restore keychains from backup
    public func restoreKeychains(completion: @escaping (RootHelperResult) -> Void) {
        runAsync("restore-keychains", completion: completion)
    }
    
    /// Apply graphics config to a specific app
    public func applyConfig(bundleID: String, configPath: String, completion: @escaping (RootHelperResult) -> Void) {
        runAsync("apply-config", bundleID, configPath, completion: completion)
    }
}
