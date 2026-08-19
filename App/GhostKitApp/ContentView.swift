//
//  ContentView.swift
//  GhostKit
//
//  Main interface: NavigationView + List of installed apps with search,
//  a top-right Menu, footer showing the iOS version, and a confirmation
//  dialog (action sheet) for per-app privileged operations.
//

import SwiftUI
import UIKit

// MARK: - Toast helper

/// Lightweight toast shown as a SwiftUI overlay.
struct ToastData: Equatable, Hashable {
    let message: String
    let icon: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(message)
        hasher.combine(icon)
    }
}

struct ToastView: View {
    let data: ToastData

    var body: some View {
        VStack(spacing: 8) {
            if let icon = data.icon {
                Image(systemName: icon)
                    .font(.title2)
            }
            Text(data.message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.75))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 12)
    }
}

extension View {
    /// Bind a toast to the view; it auto-dismisses after `duration` seconds.
    func toast(_ toast: Binding<ToastData?>, duration: TimeInterval = 2.2) -> some View {
        overlay(alignment: .center) {
            if let value = toast.wrappedValue {
                ToastView(data: value)
                    .transition(.opacity.combined(with: .scale))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation(.easeOut) { toast.wrappedValue = nil }
                        }
                    }
                    .id(value)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast.wrappedValue)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var appManager = AppListManager.shared
    @StateObject private var helper = RootHelperManager.shared

    // Action sheet / dialog state
    @State private var selectedApp: AppInfo?
    @State private var showingActionSheet: Bool = false
    @State private var showingAdvancedSheet: Bool = false

    // Navigation
    @State private var showingSettings: Bool = false
    @State private var showingDeviceInfo: Bool = false
    @State private var showingAccounts: Bool = false
    @State private var showingGraphics: Bool = false

    // Toast
    @State private var toast: ToastData?

    // Loading overlay
    @State private var loadingMessage: String?

    var body: some View {
        NavigationView {
            listContent
                .navigationTitle("GhostKit")
                .toolbar { toolbarContent }
                .searchable(text: $appManager.searchText,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "搜索应用")
                .confirmationDialog(
                    selectedApp?.name ?? "",
                    isPresented: $showingActionSheet,
                    titleVisibility: .visible
                ) {
                    mainActionSheetButtons
                }
                .confirmationDialog(
                    "高级选项",
                    isPresented: $showingAdvancedSheet,
                    titleVisibility: .visible
                ) {
                    advancedActionSheetButtons
                }
                .sheet(isPresented: $showingSettings) { SettingsView() }
                .sheet(isPresented: $showingDeviceInfo) { DeviceInfoView() }
                .sheet(isPresented: $showingAccounts) { AccountListView() }
                .sheet(isPresented: $showingGraphics) { GraphicsConfigView() }
                .overlay { loadingOverlay }
                .toast($toast)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            appManager.reload()
        }
    }

    // MARK: - List content

    @ViewBuilder private var listContent: some View {
        if appManager.isLoading {
            loadingState
        } else if appManager.displayedApps.isEmpty && appManager.searchText.isEmpty {
            if let error = appManager.loadError {
                errorState(message: error)
            } else {
                genuinelyEmptyState
            }
        } else if appManager.displayedApps.isEmpty {
            noResultsState
        } else {
            List {
                ForEach(appManager.displayedApps) { app in
                    Button {
                        selectedApp = app
                        showingActionSheet = true
                    } label: {
                        AppRowView(app: app)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) { iosVersionFooter }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.4)
            Text("正在加载应用列表…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { iosVersionFooter }
    }

    // MARK: - Error state

    private func errorState(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                appManager.reload {
                    if !appManager.displayedApps.isEmpty {
                        toast = ToastData(message: "应用列表已刷新", icon: "arrow.clockwise")
                    }
                }
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { iosVersionFooter }
    }

    // MARK: - Genuinely empty state (loaded but no apps found)

    private var genuinelyEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("暂无应用")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("下拉刷新或检查权限设置")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { iosVersionFooter }
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("未找到匹配的应用")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { iosVersionFooter }
    }

    // MARK: - Footer

    private var iosVersionFooter: some View {
        HStack {
            Spacer()
            Text("iOS \(systemVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                Button {
                    showingDeviceInfo = true
                } label: {
                    Label("设备信息", systemImage: "info.circle")
                }
                Button {
                    showingAccounts = true
                } label: {
                    Label("账号管理", systemImage: "person.crop.circle")
                }
                Button {
                    showingGraphics = true
                } label: {
                    Label("画质配置", systemImage: "gamecontroller")
                }
                Divider()
                Button {
                    appManager.reload {
                        toast = ToastData(message: "应用列表已刷新", icon: "arrow.clockwise")
                    }
                } label: {
                    Label("刷新列表", systemImage: "arrow.clockwise")
                }
                Button {
                    helper.allowPasteAll { result in
                        handleResult(result, successMsg: "已为所有应用授予粘贴权限")
                    }
                } label: {
                    Label("允许粘贴(全部)", systemImage: "doc.on.clipboard")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
            }
        }
    }

    // MARK: - Main action sheet buttons

    @ViewBuilder private var mainActionSheetButtons: some View {
        Button("刷新标识符") { performResetIDFA() }
        Button("清理Keychain") { performCleanKeychain() }
        Button("深度清理Keychain") { performDeepCleanKeychain() }
        Button("一键新机") { performResetDevice() }
        Button("清理数据库缓存") { performCleanCache() }
        Button("高级选项", role: .none) {
            showingAdvancedSheet = true
        }
        Button("取消", role: .cancel) {
            selectedApp = nil
        }
    }

    // MARK: - Advanced action sheet buttons

    @ViewBuilder private var advancedActionSheetButtons: some View {
        Button("深度清理KeyChain") {
            performDeepCleanKeychain()
        }
        Button("删除keychains") {
            performDeleteAllKeychains()
        }
        Button("恢复Keychains") {
            performRestoreKeychains()
        }
        Button("安全关闭本程序", role: .destructive) {
            safeExitApp()
        }
        Button("取消", role: .cancel) {}
    }

    // MARK: - Loading overlay

    @ViewBuilder private var loadingOverlay: some View {
        if let message = loadingMessage {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(28)
                .background(Color(.systemGray5))
                .cornerRadius(16)
            }
        }
    }

    // MARK: - Actions

    private func performResetIDFA() {
        guard let app = selectedApp else { return }
        loadingMessage = "正在刷新标识符…"
        helper.resetIDFA { result in
            loadingMessage = nil
            handleResult(result, successMsg: "已刷新 \(app.name) 的标识符", icon: "number")
        }
    }

    private func performCleanKeychain() {
        guard let app = selectedApp else { return }
        loadingMessage = "正在清理Keychain…"
        helper.cleanKeychain(bundleID: app.bundleIdentifier) { result in
            loadingMessage = nil
            handleResult(result, successMsg: "已清理 \(app.name) 的Keychain", icon: "checkmark.shield")
        }
    }

    private func performDeepCleanKeychain() {
        guard let app = selectedApp else { return }
        loadingMessage = "正在深度清理Keychain…"
        helper.deepCleanKeychain(bundleID: app.bundleIdentifier) { result in
            loadingMessage = nil
            handleResult(result, successMsg: "已深度清理 \(app.name) 的Keychain", icon: "checkmark.shield.fill")
        }
    }

    private func performResetDevice() {
        guard let app = selectedApp else { return }
        loadingMessage = "正在执行一键新机…"
        helper.resetDevice { result in
            loadingMessage = nil
            handleResult(result, successMsg: "已对 \(app.name) 执行一键新机", icon: "wand.and.stars")
        }
    }

    private func performCleanCache() {
        guard let app = selectedApp else { return }
        loadingMessage = "正在清理数据库缓存…"
        helper.cleanCache(bundleID: app.bundleIdentifier) { result in
            loadingMessage = nil
            handleResult(result, successMsg: "已清理 \(app.name) 的数据库缓存", icon: "trash")
        }
    }

    private func performDeleteAllKeychains() {
        loadingMessage = "正在删除所有keychains…"
        helper.deleteAllKeychains { result in
            loadingMessage = nil
            handleResult(result, successMsg: "已删除所有keychains", icon: "trash.slash")
        }
    }

    private func performRestoreKeychains() {
        loadingMessage = "正在恢复Keychains…"
        helper.restoreKeychains { result in
            loadingMessage = nil
            handleResult(result, successMsg: "已恢复Keychains", icon: "arrow.uturn.backward.circle")
        }
    }

    private func safeExitApp() {
        // Flush any pending writes, then terminate the process cleanly.
        toast = ToastData(message: "正在安全关闭…", icon: "power")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            exit(EXIT_SUCCESS)
        }
    }

    // MARK: - Result handling

    private func handleResult(_ result: RootHelperResult, successMsg: String, icon: String? = nil) {
        switch result {
        case .success:
            toast = ToastData(message: successMsg, icon: icon ?? "checkmark.circle")
        case .failure(let msg):
            toast = ToastData(message: "失败: \(msg)", icon: "xmark.octagon")
        }
    }
}
