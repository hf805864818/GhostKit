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
    
    /// Path to the RootHelper binary bundled inside the app.
    private lazy var rootHelperPath: String = {
        // The RootHelper binary is compiled and copied into the app bundle
        // during the build phase.  Check the main bundle first.
        let bundlePath = Bundle.main.bundlePath
        let candidate = (bundlePath as NSString).appendingPathComponent("RootHelper")
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        // Fallback: look in Frameworks or Resources subdirectories.
        let frameworksPath = (bundlePath as NSString).appendingPathComponent("Frameworks/RootHelper")
        if FileManager.default.isExecutableFile(atPath: frameworksPath) {
            return frameworksPath
        }
        // Last resort: return the default path even if it doesn't exist yet
        // (the error will be reported at execution time).
        return candidate
    }()
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Core execution
    
    /// Execute RootHelper with given arguments using posix_spawn.
    ///
    /// - Parameter args: Command and arguments to pass to the RootHelper binary
    ///   (e.g. `["clean-keychain", "com.example.app"]`).
    /// - Returns: `.success` on exit code 0, `.failure` with captured stderr otherwise.
    public func execute(_ args: [String]) -> RootHelperResult {
        guard !args.isEmpty else {
            return .failure("No command specified")
        }
        
        let binary = rootHelperPath
        
        // Verify the binary exists and is executable.
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            return .failure("RootHelper binary not found or not executable at: \(binary)")
        }
        
        // Build argv: [binary, cmd, arg1, arg2, ..., nil]
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
        
        // Create a pipe to capture stderr (RootHelper writes errors there).
        var pipefd: [Int32] = [0, 0]
        guard pipe(&pipefd) == 0 else {
            return .failure("Failed to create pipe: \(String(cString: strerror(errno)))")
        }
        
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, pipefd[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, pipefd[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, pipefd[0])
        posix_spawn_file_actions_addclose(&fileActions, pipefd[1])
        
        var pid: pid_t = 0
        let spawnResult = posix_spawnp(&pid, binary, &fileActions, nil, cArgs, environ)
        
        posix_spawn_file_actions_destroy(&fileActions)
        close(pipefd[1])
        
        if spawnResult != 0 {
            close(pipefd[0])
            return .failure("posix_spawn failed (errno=\(spawnResult)): \(String(cString: strerror(spawnResult)))")
        }
        
        // Read captured output.
        var output = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        var n: Int = 0
        repeat {
            n = read(pipefd[0], &buf, buf.count)
            if n > 0 {
                output.append(contentsOf: buf[0..<n])
            }
        } while n > 0
        close(pipefd[0])
        
        // Wait for the child process to exit.
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        
        let outputString = String(data: output, encoding: .utf8) ?? ""
        
        if WIFEXITED(status) {
            let exitCode = WEXITSTATUS(status)
            if exitCode == 0 {
                return .success
            } else {
                // Include the captured output in the error message for debugging.
                let trimmed = outputString.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return .failure("RootHelper exited with code \(exitCode)")
                } else {
                    return .failure(trimmed)
                }
            }
        } else if WIFSIGNALED(status) {
            return .failure("RootHelper terminated by signal \(WTERMSIG(status))")
        } else {
            return .failure("RootHelper exited abnormally")
        }
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
