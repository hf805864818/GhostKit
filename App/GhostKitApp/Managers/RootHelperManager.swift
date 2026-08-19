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

    // MARK: - Core execution (posix_spawn)

    func run(arguments: [String], completion: @escaping (RootHelperResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeHelper(arguments: arguments)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Spawn RootHelper via posix_spawn, capture stdout/stderr, and return result.
    private func executeHelper(arguments: [String]) -> RootHelperResult {
        let path = self.helperPath

        // Check if RootHelper binary exists
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure("RootHelper binary not found at: \(path)")
        }

        // Build argv array (C strings)
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

        // Create pipes for stdout and stderr
        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            return .failure("Failed to create pipes")
        }

        // Set up spawn file actions
        var fileActions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[1])
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[1])

        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }

        // Spawn the process
        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, path, &fileActions, nil, argv, nil)

        // Close write ends of pipes in parent
        close(stdoutPipe[1])
        close(stderrPipe[1])

        if spawnResult != 0 {
            close(stdoutPipe[0])
            close(stderrPipe[0])
            return .failure("Failed to spawn RootHelper (errno: \(spawnResult))")
        }

        // Read stdout
        let stdoutData = self.readData(from: stdoutPipe[0])
        close(stdoutPipe[0])

        // Read stderr
        let stderrData = self.readData(from: stderrPipe[0])
        close(stderrPipe[0])

        // Wait for exit
        var status: Int32 = 0
        waitpid(pid, &status, 0)

        let stdoutStr = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if status == 0 {
            return .success(stdoutStr.isEmpty ? "OK" : stdoutStr)
        } else {
            let msg = stderrStr.isEmpty ? stdoutStr : stderrStr
            return .failure(msg.isEmpty ? "RootHelper exited with code \(status)" : msg)
        }
    }

    /// Read all data from a file descriptor.
    private func readData(from fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var bytesRead = read(fd, &buffer, buffer.count)
        while bytesRead > 0 {
            data.append(contentsOf: buffer[0..<bytesRead])
            bytesRead = read(fd, &buffer, buffer.count)
        }
        return data
    }
}
