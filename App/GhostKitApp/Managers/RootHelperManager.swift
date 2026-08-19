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
    private var bundledHelperPath: String {
        (Bundle.main.bundlePath as NSString).appendingPathComponent("RootHelper")
    }

    /// Path where RootHelper is copied for execution.
    /// iOS may block execution of binaries from inside the app bundle.
    /// Copying to /tmp/ and executing from there is more reliable.
    private var executableHelperPath: String {
        "/tmp/GhostKitRootHelper"
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

        // Step 1: Ensure RootHelper binary is available and executable
        let execPath = self.prepareHelperBinary()
        guard let path = execPath else {
            return .failure("RootHelper binary not found in app bundle at: \(self.bundledHelperPath)")
        }

        // Step 2: Build argv array as C strings
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

        // Step 3: Allocate output buffer (1 MB)
        let bufferSize = 1_048_576
        let outputBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { outputBuffer.deallocate() }

        // Step 4: Call C bridge function
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
        } else if exitCode < 0 {
            // Any negative return from SpawnBridge means posix_spawn or
            // pre-spawn checks failed.  The output buffer contains a
            // diagnostic message from SpawnBridge.c.
            let errnoVal = -exitCode
            let errnoDesc = String(cString: strerror(errnoVal))
            return .failure(output.isEmpty
                ? "无法启动 RootHelper (errno=\(errnoVal): \(errnoDesc))"
                : output)
        } else {
            // Positive exit code from RootHelper itself
            return .failure(output.isEmpty
                ? "RootHelper exited with code \(exitCode)"
                : output)
        }
    }

    /// Prepare the RootHelper binary for execution.
    /// Copies it from the app bundle to /tmp/ and ensures it's executable.
    /// Returns the path to use for execution, or nil if the binary doesn't exist.
    private func prepareHelperBinary() -> String? {
        let fm = FileManager.default

        // Check if bundled RootHelper exists
        guard fm.fileExists(atPath: bundledHelperPath) else {
            NSLog("[GhostKit] RootHelper not found at: %@", bundledHelperPath)
            return nil
        }

        // Copy to /tmp/ for execution (avoids app bundle sandbox restrictions)
        let tmpPath = executableHelperPath
        if fm.fileExists(atPath: tmpPath) {
            // Check if it's the same as the bundled version
            let bundledAttrs = try? fm.attributesOfItem(atPath: bundledHelperPath)
            let tmpAttrs = try? fm.attributesOfItem(atPath: tmpPath)
            let bundledSize = bundledAttrs?[.size] as? Int ?? 0
            let tmpSize = tmpAttrs?[.size] as? Int ?? 0
            if bundledSize != tmpSize {
                try? fm.removeItem(atPath: tmpPath)
                try? fm.copyItem(atPath: bundledHelperPath, toPath: tmpPath)
            }
        } else {
            do {
                try fm.copyItem(atPath: bundledHelperPath, toPath: tmpPath)
                NSLog("[GhostKit] Copied RootHelper to %@", tmpPath)
            } catch {
                NSLog("[GhostKit] Failed to copy RootHelper to /tmp/: %@", error.localizedDescription)
                // Fall back to bundled path
                return bundledHelperPath
            }
        }

        // Ensure executable permissions
        chmod(tmpPath, 0o755)

        return tmpPath
    }
}
