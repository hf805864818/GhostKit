//
//  GraphicsConfigView.swift
//  GhostKit
//
//  Game graphics quality configuration page.
//  Select a game, pick a preset (Low / Medium / High / Ultra / Custom),
//  then apply or restore.
//

import SwiftUI

// MARK: - Models

enum GraphicsPreset: String, CaseIterable, Identifiable {
    case low = "流畅 (最低)"
    case medium = "平衡 (中等)"
    case high = "高清 (高)"
    case ultra = "极致 (超清)"
    case custom = "自定义"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .low:    return "speedometer"
        case .medium: return "gauge.medium"
        case .high:   return "gauge.high"
        case .ultra:  return "gauge.with.dots.needle.67percent"
        case .custom: return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .low:    return "关闭抗锯齿, 30 FPS, 最低分辨率"
        case .medium: return "开启抗锯齿, 45 FPS, 中等分辨率"
        case .high:   return "开启抗锯齿, 60 FPS, 高分辨率"
        case .ultra:  return "全部开启, 120 FPS, 原生分辨率"
        case .custom: return "手动调整各项参数"
        }
    }

    var configPayload: String {
        switch self {
        case .low:
            return "{\"fps\":30,\"resolution\":0.5,\"anti_aliasing\":0,\"shadows\":0,\"textures\":0}"
        case .medium:
            return "{\"fps\":45,\"resolution\":0.75,\"anti_aliasing\":1,\"shadows\":1,\"textures\":1}"
        case .high:
            return "{\"fps\":60,\"resolution\":1.0,\"anti_aliasing\":1,\"shadows\":1,\"textures\":2}"
        case .ultra:
            return "{\"fps\":120,\"resolution\":1.0,\"anti_aliasing\":1,\"shadows\":2,\"textures\":2}"
        case .custom:
            return "{\"fps\":60,\"resolution\":1.0,\"anti_aliasing\":1,\"shadows\":1,\"textures\":1}"
        }
    }
}

// MARK: - GraphicsConfigView

struct GraphicsConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var appManager = AppListManager.shared

    @State private var selectedGame: AppInfo?
    @State private var selectedPreset: GraphicsPreset = .high
    @State private var showingGamePicker: Bool = false
    @State private var loading: Bool = false
    @State private var toast: ToastData?

    private let helper = RootHelperManager.shared

    var body: some View {
        NavigationView {
            List {
                Section("选择游戏") {
                    Button {
                        showingGamePicker = true
                    } label: {
                        HStack {
                            if let icon = selectedGame?.icon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                Image(systemName: "gamecontroller")
                                    .font(.title2)
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(.accentColor)
                            }
                            VStack(alignment: .leading) {
                                Text(selectedGame?.name ?? "点击选择游戏")
                                    .font(.system(size: 15, weight: .medium))
                                if let id = selectedGame?.bundleIdentifier {
                                    Text(id)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("画质预设") {
                    ForEach(GraphicsPreset.allCases) { preset in
                        presetRow(preset)
                    }
                }

                Section("当前配置") {
                    HStack {
                        Image(systemName: selectedPreset.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 26)
                        VStack(alignment: .leading) {
                            Text(selectedPreset.rawValue)
                                .font(.system(size: 15, weight: .medium))
                            Text(selectedPreset.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        applyConfig()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.bolt")
                            Text("应用画质配置")
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.accentColor)
                    }
                    .disabled(selectedGame == nil)

                    Button {
                        restoreConfig()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text("恢复默认配置")
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.orange)
                    }
                    .disabled(selectedGame == nil)
                }
            }
            .navigationTitle("画质配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingGamePicker) {
                gamePicker
            }
            .overlay { loadingOverlay }
            .toast($toast)
        }
    }

    // MARK: - Preset row

    private func presetRow(_ preset: GraphicsPreset) -> some View {
        Button {
            withAnimation { selectedPreset = preset }
        } label: {
            HStack {
                Image(systemName: preset.icon)
                    .foregroundColor(selectedPreset == preset ? .accentColor : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading) {
                    Text(preset.rawValue)
                        .foregroundColor(.primary)
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if selectedPreset == preset {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Game picker sheet

    private var gamePicker: some View {
        NavigationView {
            List {
                ForEach(appManager.displayedApps) { app in
                    Button {
                        selectedGame = app
                        showingGamePicker = false
                    } label: {
                        AppRowView(app: app)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("选择游戏")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $appManager.searchText, prompt: "搜索")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showingGamePicker = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func applyConfig() {
        guard let game = selectedGame else { return }
        loading = true
        let config = selectedPreset.configPayload

        // Write the JSON payload to a temporary file for RootHelper.
        let tempPath = NSTemporaryDirectory().appending("ghostkit_config.json")
        do {
            try config.write(toFile: tempPath, atomically: true, encoding: .utf8)
        } catch {
            loading = false
            toast = ToastData(message: "配置写入失败", icon: "xmark.octagon")
            return
        }

        helper.applyConfig(bundleID: game.bundleIdentifier, configPath: tempPath) { result in
            loading = false
            switch result {
            case .success:
                toast = ToastData(message: "已应用\(selectedPreset.rawValue)配置", icon: "checkmark.circle")
            case .failure(let msg):
                toast = ToastData(message: "应用失败: \(msg)", icon: "xmark.octagon")
            }
        }
    }

    private func restoreConfig() {
        guard let game = selectedGame else { return }
        loading = true
        selectedPreset = .medium
        let tempPath = NSTemporaryDirectory().appending("ghostkit_config.json")
        let config = GraphicsPreset.medium.configPayload
        try? config.write(toFile: tempPath, atomically: true, encoding: .utf8)

        helper.applyConfig(bundleID: game.bundleIdentifier, configPath: tempPath) { result in
            loading = false
            switch result {
            case .success:
                toast = ToastData(message: "已恢复默认配置", icon: "arrow.uturn.backward.circle")
            case .failure(let msg):
                toast = ToastData(message: "恢复失败: \(msg)", icon: "xmark.octagon")
            }
        }
    }

    // MARK: - Loading overlay

    @ViewBuilder private var loadingOverlay: some View {
        if loading {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.4)
                        .tint(.white)
                    Text("正在应用配置…")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(28)
                .background(Color(.systemGray5))
                .cornerRadius(16)
            }
        }
    }
}
