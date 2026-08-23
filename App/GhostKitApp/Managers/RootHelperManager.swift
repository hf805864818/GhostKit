//
//  RootHelperManager.swift
//  GhostKit
//
//  Bridges the SwiftUI layer with the C `RootHelper` binary.
//  Uses posix_spawn (not Process, which is macOS-only) to execute
//  the RootHelper binary.
//
//  PRIVILEGE MODEL:
//    - RootHelper attempts to elevate to root via setuid(0)
//    - In TrollStore, this depends on having proper entitlements
//    - In rootful jailbreak, RootHelper runs as root directly
//    - In rootless jailbreak (Dopamine/RelaXin), use Tweak instead
//
//  FALLBACK STRATEGY:
//    - If RootHelper fails due to permissions, user should install .deb Tweak
//    - Tweak runs in SpringBoard as root and handles system operations
//    - App sends Darwin notifications to Tweak for privileged operations
