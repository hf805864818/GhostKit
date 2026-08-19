//
//  RootHelperManager.swift
//  GhostKit
//
//  Bridges the SwiftUI layer with the C `RootHelper` binary.
//  Every privileged operation is delegated to RootHelper, which is spawned
//  as a separate Process so it inherits the TrollStore entitlements and runs
//  with the same (root) privileges as the host app.
//

import Foundation

// MARK: - Result type

enum RootHelperResult: Equatable {
    case success(String)
    case failure(String)
}

// MARK: - RootHelperManager

final class RootHelperManager {

    static let shared = RootHelperManager()

    /// Path to the bundled RootHelper binary inside the .app bundle.
    private lazy var helperPath: String = {
        let bundle = Bundle.main.bundlePath
        return (bundle as NSString).appendingPathComponent("RootHelper")
    }()

    private init() {}

    // MARK: - Public API

    // -- Keychain operations -----------------------------------------------

    /// Remove keychain entries that belong to `bundleID`.
    func cleanKeychain(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-keychain", bundleID], completion: completion)
    }

    /// Aggressively remove every keychain entry for `bundleID` (incl. groups).
    func deepCleanKeychain(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["deep-clean-keychain", bundleID], completion: completion)
    }

    /// Delete all keychain databases entirely (very destructive).
    func deleteAllKeychains(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["delete-all-keychains"], completion: completion)
    }

    /// Restore the keychain databases from the backup created by delete-all.
    func restoreKeychains(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["restore-keychains"], completion: completion)
    }

    // -- IDFA ---------------------------------------------------------------

    /// Reset / rotate the advertising identifier (IDFA).
    func resetIDFA(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["reset-idfa"], completion: completion)
    }

    // -- Cache / data -------------------------------------------------------

    /// Clear temporary & cached files for `bundleID`.
    func cleanCache(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-cache", bundleID], completion: completion)
    }

    /// Wipe the data directory contents for `bundleID`.
    func cleanDataDir(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-data-dir", bundleID], completion: completion)
    }

    /// Clear web cookies & local storage for `bundleID`.
    func cleanCookies(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["clean-cookies", bundleID], completion: completion)
    }

    // -- Device -----------------------------------------------------------

    /// Perform a full "new device" reset (IDFA, keychain, caches, ID records).
    func resetDevice(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["reset-device"], completion: completion)
    }

    /// Grant paste permission for every app by modifying TCC.db.
    func allowPasteAll(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["allow-paste-all"], completion: completion)
    }

    /// Restart SpringBoard (used after keychain / TCC changes).
    func respring(completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["respring"], completion: completion)
    }

    /// Uninstall an application by bundle identifier.
    func uninstallApp(bundleID: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["uninstall", bundleID], completion: completion)
    }

    // -- Graphics configuration -------------------------------------------

    /// Apply a game graphics quality preset written at `configPath` to `bundleID`.
    func applyConfig(bundleID: String, configPath: String, completion: @escaping (RootHelperResult) -> Void) {
        run(arguments: ["apply-config", bundleID, configPath], completion: completion)
    }

    // MARK: - Core execution

    /// Spawn RootHelper with the given arguments and return stdout/stderr.
    func run(arguments: [String], completion: @escaping (RootHelperResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Build the full command: RootHelper <args...>
            // The helper is a setuid-style binary that performs posix_spawn
            // of privileged commands as root.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.helperPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                // If Process can't exec directly (rare under TrollStore),
                // fall back to running through /bin/sh -c.
                let shProcess = Process()
                shProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
                var escaped = [self.helperPath] + arguments.map { "'\($0)'" }
                let joined = escaped.joined(separator: " ")
                shProcess.arguments = ["-c", joined]
                shProcess.standardOutput = stdoutPipe
                shProcess.standardError = stderrPipe
                do {
                    try shProcess.run()
                    shProcess.waitUntilExit()
                    self.collectOutput(process: shProcess,
                                       stdout: stdoutPipe,
                                       stderr: stderrPipe,
                                       completion: completion)
                    return
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure("Failed to launch RootHelper: \(error.localizedDescription)"))
                    }
                    return
                }
            }

            process.waitUntilExit()
            self.collectOutput(process: process,
                               stdout: stdoutPipe,
                               stderr: stderrPipe,
                               completion: completion)
        }
    }

    // MARK: - Output collection

    private func collectOutput(
        process: Process,
        stdout: Pipe,
        stderr: Pipe,
        completion: @escaping (RootHelperResult) -> Void
    ) {
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""

        let result: RootHelperResult
        if process.terminationStatus == 0 {
            result = .success(stdoutString.isEmpty ? "OK" : stdoutString)
        } else {
            let message = stderrString.isEmpty ? stdoutString : stderrString
            result = .failure(message.isEmpty ? "RootHelper exited with code \(process.terminationStatus)" : message)
        }

        DispatchQueue.main.async {
            completion(result)
        }
    }
}
