//
//  RootHelperManager.swift
//  GhostKit
//
//  Bridges the SwiftUI layer with the C `RootHelper` binary.
//  Uses SpawnBridge.c (posix_spawn C bridge) because Swift on iOS
//  blocks direct process spawning APIs (popen/system).
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
    @Published public var lastOutput: String?
    
    /// Path to the RootHelper binary bundled inside the app.
    /// The postBuildScript in project.yml compiles RootHelper.c and
    /// copies the binary into the .app bundle root.
    private lazy var rootHelperPath: String = {
        let bundlePath = Bundle.main.bundlePath
        let candidate = (bundlePath as NSString).appendingPathComponent("RootHelper")
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        // Fallback: Frameworks subdirectory
        let fwPath = (bundlePath as NSString).appendingPathComponent("Frameworks/RootHelper")
        if FileManager.default.isExecutableFile(atPath: fwPath) {
            return fwPath
        }
        return candidate
    }()
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Core execution via SpawnBridge C bridge
    
    /// Execute RootHelper with given arguments.
    ///
    /// Uses `spawn_and_capture()` from SpawnBridge.c — a C bridge for
    /// posix_spawn that works on iOS (Swift blocks popen/system directly).
    ///
    /// - Parameter args: Command and arguments to pass to the RootHelper binary
    ///   (e.g. `["clean-keychain", "com.example.app"]`).
    /// - Returns: `.success` on exit code 0, `.failure` with captured output otherwise.
    public func execute(_ args: [String]) -> RootHelperResult {
        guard !args.isEmpty else {
            return .failure("No command specified")
        }
        
        let binary = rootHelperPath
        
        // Verify the binary exists and is executable.
        guard FileManager.default.fileExists(atPath: binary) else {
            return .failure("RootHelper binary not found at: \(binary)\nThis usually means the postBuildScript did not run during compilation.")
        }
        
        // Build C argv array: [binary, arg0, arg1, ..., nil]
        // Using strdup + free for automatic memory management.
        var cArgs: [UnsafeMutablePointer<CChar>?] = []
        cArgs.append(strdup(binary))
        for arg in args {
            cArgs.append(strdup(arg))
        }
        cArgs.append(nil)
        
        defer {
            for ptr in cArgs where ptr != nil {
                free(ptr)
            }
        }
        
        // Output buffer — 16 KB is plenty for RootHelper's stderr/stdout.
        let outSize = 16384
        var outputBuffer = [CChar](repeating: 0, count: outSize)
        
        // Call the C bridge function from SpawnBridge.c
        // This handles posix_spawn, pipe setup, output capture, and waitpid.
        let exitCode = spawn_and_capture(
            binary,
            cArgs,
            &outputBuffer,
            Int32(outSize)
        )
        
        let output = String(cString: outputBuffer)
        
        // Store the last output for debugging
        lastOutput = output
        
        if exitCode == 0 {
            return .success
        } else {
            // Include the captured stderr/stdout in the error message.
            // RootHelper writes detailed diagnostics to stderr.
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .failure("RootHelper exited with code \(exitCode) (no output captured)")
            } else {
                return .failure(trimmed)
            }
        }
    }
    
    // MARK: - Async wrapper
    
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
