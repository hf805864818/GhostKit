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

    // MARK: - Core execution (C bridge via SpawnBridge)

    func run(arguments: [String], completion: @escaping (RootHelperResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeHelper(arguments: arguments)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Execute RootHelper via C bridge (posix_spawn wrapper).
    private func executeHelper(arguments: [String]) -> RootHelperResult {
        let path = self.helperPath

        // Check if RootHelper binary exists
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure("RootHelper binary not found at: \(path)")
        }

        // Build argv array as C strings
        let argc = arguments.count + 2  // path + args + NULL
        var argv: [UnsafeMutablePointer<CChar>?] = []
        argv.append(strdup(path))
        for arg in arguments {
            argv.append(strdup(arg))
        }
        argv.append(nil)

        defer {
            for ptr in argv {
                if ptr != nil { free(ptr) }
            }
        }

        // Allocate output buffer (1 MB should be enough)
        let bufferSize = 1_048_576
        let outputBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { outputBuffer.deallocate() }

        // Call C bridge function
        let exitCode = spawn_and_capture(
            path,
            argv,
            outputBuffer,
            Int32(bufferSize)
        )

        let output = String(cString: outputBuffer)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if exitCode == 0 {
            return .success(output.isEmpty ? "OK" : output)
        } else if exitCode == -1 {
            return .failure("Failed to spawn RootHelper (posix_spawn error)")
        } else if exitCode == -2 {
            return .failure("RootHelper terminated abnormally")
        } else {
            return .failure(output.isEmpty
                ? "RootHelper exited with code \(exitCode)"
                : output)
        }
    }
}
