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
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let success = try container.decode(Bool.self, forKey: .success)
        if success {
            self = .success
        } else {
            let error = try container.decodeIfPresent(String.self, forKey: .error) ?? "Unknown error"
            self = .failure(error)
        }
    }
    
    func encode(to encoder: Encoder) throws {
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
    
    @Published var lastResult: RootHelperResult?
    
    // MARK: - Methods
    
    /// Execute RootHelper with given arguments
    func execute(_ args: String...) -> RootHelperResult {
        // Implementation uses posix_spawn to run RootHelper binary
        // For now, return a placeholder result
        return .success
    }
}
