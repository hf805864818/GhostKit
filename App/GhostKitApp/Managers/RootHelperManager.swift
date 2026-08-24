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
public struct RootHelperResult: Codable {
    let success: Bool
    let output: String
    let error: String
}

/// Manager that handles RootHelper operations
public class RootHelperManager: ObservableObject {
    public static let shared = RootHelperManager()
    
    // MARK: - Methods
    
    private func spawnAndCapture(_ args: [String]) -> String? {
        // Implementation needed - using existing logic
        return nil
    }
}
