//
//  SettingsView.swift
//  GhostKit
//
//  Settings page: language switch and about information.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.language") private var language: String = Locale.current.languageCode ?? "zh"
    @AppStorage("app.darkMode") private var darkMode: Bool = false
    @AppStorage("app.confirmBeforeAction") private var confirmBeforeAction: Bool = true

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        NavigationView {
            Form {
                Section("通用") {
                    Picker("语言", selection: $language) {
                        Text("简体中文").tag("zh")
                        Text("English").tag("en")
                        Text("繁體中文").tag("zh-Hant")
                        Text("日本語").tag("ja")
                    }

                    Toggle("深色模式", isOn: $darkMode)

                    Toggle("操作前确认", isOn: $confirmBeforeAction)
                }

                Section("功能快捷") {
                    NavigationLink {
                        DeviceInfoView()
                    } label: {
                        Label("设备信息", systemImage: "info.circle")
                    }
                    NavigationLink {
                        AccountListView()
                    } label: {
                        Label("App Store 账号管理", systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        GraphicsConfigView()
                    } label: {
                        Label("游戏画质配置", systemImage: "gamecontroller")
                    }
                }

                Section("关于") {
                    infoRow(title: "名称", value: "GhostKit")
                    infoRow(title: "版本", value: "\(version) (\(build))")
                    infoRow(title: "最低系统", value: "iOS 15.0")
                    infoRow(title: "类型", value: "TrollStore App")
                    infoRow(title: "权限", value: "Root (RootHelper)")
                }

                Section {
                    Link(destination: URL(string: "https://t.me/hfkj520")!) {
                        HStack {
                            Label("Telegram 频道", systemImage: "paperplane")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
