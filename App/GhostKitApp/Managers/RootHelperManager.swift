//
//  RootHelperManager.swift
//  GhostKit
//
//  Bridges the SwiftUI layer with the C `RootHelper` binary.
//  Uses posix_spawn (not Process, which is macOS-only) to execute
//  the RootHelper binary with TrollStore root privileges.
//

import Foundation
import Darwin

// MARK: - Result type

enum RootHelperResult: Equatable {
    case success(String)
    case failure(String)
}

// MARK: - RootHelperManager

final class RootHelperManager: ObservableObject {

    static let shared = RootHelperManager()

    /// Path to the bundled RootHelper binary inside the .app bundle.
    private var helperPath: String {
        (Bundle.main.bundlePath as NSString).appendingPathComponent("RootHelper")
    }

    private init() {}

    // MARK: - Public API

    // -- Keychain operations -----------------------------------------------

    func cleanKeychain(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-keychain", bundleID], completion: completion)
    }

    func deepCleanKeychain(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["deep-clean-keychain", bundleID], completion: completion)
    }

    func deleteAllKeychains(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["delete-all-keychains"], completion: completion)
    }

    func restoreKeychains(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["restore-keychains"], completion: completion)
    }

    // -- IDFA ---------------------------------------------------------------

    func resetIDFA(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["reset-idfa"], completion: completion)
    }

    // -- Cache / data -------------------------------------------------------

    func cleanCache(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-cache", bundleID], completion: completion)
    }

    func cleanDataDir(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-data-dir", bundleID], completion: completion)
    }

    func cleanCookies(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-cookies", bundleID], completion: completion)
    }

    // -- Device -----------------------------------------------------------

    func resetDevice(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["reset-device"], completion: completion)
    }

    func allowPasteAll(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["allow-paste-all"], completion: completion)
    }

    func respring(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["respring"], completion: completion)
    }

    func uninstallApp(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["uninstall", bundleID], completion: completion)
    }

    // -- Graphics configuration -------------------------------------------

    func applyConfig(bundleID: String, configPath: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["apply-config", bundleID, configPath], completion: completion)
    }

    // MARK: - Core execution (popen)

    func run(arguments: [String], completion: @escaping (RootHelperResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeHelper(arguments: arguments)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Execute RootHelper via popen, capture combined stdout+stderr.
    private func executeHelper(arguments: [String]) -> RootHelperResult {
        let path = self.helperPath

        // Check if RootHelper binary exists
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure("RootHelper binary not found at: \(path)")
        }

        // Build command string with 2>&1 to capture stderr in stdout
        let escapedArgs = arguments.map { "'\($0)'" }.joined(separator: " ")
        let command = "'\(path)' \(escapedArgs) 2>&1"

        // Use popen to capture combined output
        guard let pipe = popen(command, "r") else {
            return .failure("Failed to open pipe to RootHelper")
        }

        var output = ""
        var buffer = [CChar](repeating: 0, count: 4096)
        while fgets(&buffer, Int32(buffer.count), pipe) != nil {
            output += String(cString: buffer)
        }

        let status = pclose(pipe)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if status == 0 {
            return .success(trimmedOutput.isEmpty ? "OK" : trimmedOutput)
        } else {
            return .failure(trimmedOutput.isEmpty
                ? "RootHelper exited with code \(status)"
                : trimmedOutput)
        }
    }
}
