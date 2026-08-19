//
//  ActionSheetView.swift
//  GhostKit
//
//  Reusable SwiftUI representation of the per-app action menu.
//  Mirrors the confirmationDialog used in ContentView but exposed as a
//  standalone view so it can be presented from other contexts.
//

import SwiftUI

/// Identifies a single action presented in the action sheet.
enum AppAction: String, CaseIterable, Identifiable {
    case resetIDFA        = "刷新标识符"
    case cleanKeychain    = "清理Keychain"
    case deepCleanKey     = "深度清理Keychain"
    case resetDevice      = "一键新机"
    case cleanCache       = "清理数据库缓存"
    case advanced         = "高级选项"
    case cancel           = "取消"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .resetIDFA:     return "number"
        case .cleanKeychain: return "checkmark.shield"
        case .deepCleanKey:  return "checkmark.shield.fill"
        case .resetDevice:   return "wand.and.stars"
        case .cleanCache:    return "trash"
        case .advanced:      return "slider.horizontal.3"
        case .cancel:        return "xmark"
        }
    }

    var role: ButtonRole? {
        self == .cancel ? .cancel : nil
    }
}

/// Advanced sub-menu actions.
enum AdvancedAction: String, CaseIterable, Identifiable {
    case deepCleanKey   = "深度清理KeyChain"
    case deleteKeys     = "删除keychains"
    case restoreKeys    = "恢复Keychains"
    case safeExit       = "安全关闭本程序"
    case cancel         = "取消"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .deepCleanKey: return "checkmark.shield.fill"
        case .deleteKeys:   return "trash.slash"
        case .restoreKeys:  return "arrow.uturn.backward.circle"
        case .safeExit:     return "power"
        case .cancel:       return "xmark"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .safeExit: return .destructive
        case .cancel:   return .cancel
        default:        return nil
        }
    }
}

struct ActionSheetView: View {
    let app: AppInfo?
    let onSelect: (AppAction) -> Void
    let onSelectAdvanced: (AdvancedAction) -> Void

    @State private var showingAdvanced: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                if let icon = app?.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app?.name ?? "未选择应用")
                        .font(.headline)
                    Text(app?.bundleIdentifier ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))

            Divider()

            // Primary actions
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(AppAction.allCases) { action in
                        Button {
                            if action == .advanced {
                                showingAdvanced = true
                            } else {
                                onSelect(action)
                            }
                        } label: {
                            actionRow(for: action)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(isPresented: $showingAdvanced) {
            advancedSheet
        }
    }

    // MARK: - Rows

    private func actionRow(for action: AppAction) -> some View {
        HStack(spacing: 14) {
            Image(systemName: action.icon)
                .font(.system(size: 16))
                .foregroundColor(action == .cancel ? .secondary : .accentColor)
                .frame(width: 26)
            Text(action.rawValue)
                .foregroundColor(action == .cancel ? .secondary : .primary)
            Spacer()
            if action == .advanced {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Advanced sheet

    private var advancedSheet: some View {
        NavigationView {
            List {
                Section("高级选项") {
                    ForEach(AdvancedAction.allCases) { action in
                        Button {
                            onSelectAdvanced(action)
                        } label: {
                            HStack {
                                Image(systemName: action.icon)
                                    .frame(width: 26)
                                Text(action.rawValue)
                                    .foregroundColor(action.role == .destructive ? .red : .primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("高级选项")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
