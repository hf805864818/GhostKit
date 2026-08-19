//
//  AppListManager.swift
//  GhostKit
//
//  Reads the list of installed applications using the private
//  LSApplicationWorkspace API (resolved at runtime via NSClassFromString).
//

import Foundation
import UIKit

// MARK: - AppInfo model

/// Lightweight representation of an installed application.
struct AppInfo: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    let version: String
    let shortVersion: String
    let icon: UIImage?
    let bundleURL: URL?
    let dataContainerURL: URL?
    /// `true` for system / stock applications.
    let isSystemApp: Bool

    var id: String { bundleIdentifier }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
}

// MARK: - AppListManager

final class AppListManager: ObservableObject {

    static let shared = AppListManager()

    /// Published list of installed applications.
    @Published private(set) var installedApps: [AppInfo] = []
    @Published private(set) var isLoading: Bool = false

    /// Optional filter text published from the search bar.
    @Published var searchText: String = "" {
        didSet { applyFilter() }
    }

    private var allApps: [AppInfo] = []
    private var filteredApps: [AppInfo] = []

    /// Computed property consumed by SwiftUI views.
    var displayedApps: [AppInfo] {
        filteredApps.isEmpty && searchText.isEmpty ? allApps : filteredApps
    }

    // MARK: - Private LSApplicationWorkspace bridge

    /// Resolve the private `LSApplicationWorkspace` class and `defaultWorkspace`
    /// selector at runtime so the project compiles without a private framework.
    private lazy var applicationWorkspaceClass: AnyClass? = {
        NSClassFromString("LSApplicationWorkspace")
    }()

    private lazy var defaultWorkspace: NSObject? = {
        guard let cls = applicationWorkspaceClass as? NSObject.Type else { return nil }
        let defaultWorkspaceSelector = NSSelectorFromString("defaultWorkspace")
        guard cls.responds(to: defaultWorkspaceSelector) else { return nil }
        let workspace = cls.perform(defaultWorkspaceSelector)?.takeUnretainedValue()
        return workspace as? NSObject
    }()

    private init() {}

    // MARK: - Public API

    /// Refresh the cached list of installed applications from the system.
    func reload(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = self.getAllInstalledAppsDirect()
            DispatchQueue.main.async {
                self.allApps = apps
                self.applyFilter()
                self.isLoading = false
                completion?()
            }
        }
    }

    /// Direct, synchronous enumeration of every installed application using the
    /// private LSApplicationWorkspace API.
    /// Falls back to an empty array when the private API is unavailable.
    func getAllInstalledAppsDirect() -> [AppInfo] {
        guard let workspace = defaultWorkspace else { return [] }

        let allAppsSelector = NSSelectorFromString("allInstalledApplications")
        guard workspace.responds(to: allAppsSelector) else { return [] }

        guard let rawList = workspace.perform(allAppsSelector)?.takeUnretainedValue() as? [AnyObject] else {
            return []
        }

        var result: [AppInfo] = []
        result.reserveCapacity(rawList.count)

        for proxy in rawList {
            let bundleID = string(for: proxy, selector: "applicationIdentifier") ?? ""
            if bundleID.isEmpty { continue }

            let name = string(for: proxy, selector: "localizedName") ??
                       string(for: proxy, selector: "itemName") ??
                       bundleID
            let version = string(for: proxy, selector: "version") ?? "1.0"
            let shortVersion = string(for: proxy, selector: "shortVersionString") ?? version
            let bundlePath = string(for: proxy, selector: "bundleURL") ?? ""
            let containerPath = string(for: proxy, selector: "dataContainerURL") ?? ""
            let bundleURL = bundlePath.isEmpty ? nil : URL(fileURLWithPath: bundlePath)
            let containerURL = containerPath.isEmpty ? nil : URL(fileURLWithPath: containerPath)
            let isSystem = self.boolValue(for: proxy, selector: "isSystemApplication") ?? false

            let icon = self.loadIcon(for: proxy, bundleID: bundleID)

            result.append(AppInfo(
                bundleIdentifier: bundleID,
                name: name,
                version: version,
                shortVersion: shortVersion,
                icon: icon,
                bundleURL: bundleURL,
                dataContainerURL: containerURL,
                isSystemApp: isSystem
            ))
        }

        result.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return result
    }

    /// Case-insensitive keyword search across name and bundle identifier.
    func search(keyword: String) -> [AppInfo] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allApps }

        let lowercased = trimmed.lowercased()
        return allApps.filter { info in
            info.name.lowercased().contains(lowercased) ||
            info.bundleIdentifier.lowercased().contains(lowercased)
        }
    }

    // MARK: - Private helpers

    private func applyFilter() {
        filteredApps = search(keyword: searchText)
    }

    /// Read a string value from an LSApplicationProxy using KVC-like selectors.
    private func string(for proxy: AnyObject, selector: String) -> String? {
        let sel = NSSelectorFromString(selector)
        guard proxy.responds(to: sel) else { return nil }
        let value = proxy.perform(sel)?.takeUnretainedValue()
        if let str = value as? String { return str }
        if let url = value as? URL { return url.path }
        return nil
    }

    /// Read a boolean value from an LSApplicationProxy.
    private func boolValue(for proxy: AnyObject, selector: String) -> Bool? {
        let sel = NSSelectorFromString(selector)
        guard proxy.responds(to: sel) else { return nil }
        let value = proxy.perform(sel)?.takeUnretainedValue()
        return (value as? NSNumber)?.boolValue
    }

    /// Resolve and load an application icon.
    /// Prefers the `iconForFormat` private selector, then falls back to
    /// reading Info.plist + AppIcon60@2x.png from the bundle on disk.
    private func loadIcon(for proxy: AnyObject, bundleID: String) -> UIImage? {
        let iconForFormatSelector = NSSelectorFromString("iconForScale:")
        if proxy.responds(to: iconForFormatSelector) {
            if let icon = proxy.perform(iconForFormatSelector, with: 2.0)?.takeUnretainedValue() as? UIImage {
                return icon
            }
        }

        // Fallback: read icon file directly from the app bundle.
        if let bundlePath = string(for: proxy, selector: "bundleURL"),
           !bundlePath.isEmpty {
            let bundleURL = URL(fileURLWithPath: bundlePath)
            let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
            if let info = NSDictionary(contentsOf: infoPlistURL),
               let icons = info["CFBundleIcons"] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String],
               let largest = files.last {
                let iconURL = bundleURL.appendingPathComponent("\(largest)@2x.png")
                if let data = try? Data(contentsOf: iconURL) {
                    return UIImage(data: data)
                }
                let plainURL = bundleURL.appendingPathComponent("\(largest).png")
                if let data = try? Data(contentsOf: plainURL) {
                    return UIImage(data: data)
                }
            }
        }

        // Generic placeholder otherwise.
        return UIImage(systemName: "app.fill")
    }
}
