//
//  AccountListView.swift
//  GhostKit
//
//  App Store account management page.
//  Lists saved Apple ID accounts, allows adding, deleting and switching.
//

import SwiftUI

// MARK: - Account model

struct AppleAccount: Identifiable, Hashable {
    let id = UUID()
    let appleID: String
    let password: String
    let region: String
    var isActive: Bool

    var maskedPassword: String {
        String(repeating: "*", count: max(password.count, 4))
    }
}

// MARK: - AccountListView

struct AccountListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [AppleAccount] = [
        AppleAccount(appleID: "main@icloud.com", password: "password123", region: "中国", isActive: true),
        AppleAccount(appleID: "us@gmail.com", password: "password456", region: "美国", isActive: false),
        AppleAccount(appleID: "jp@yahoo.com", password: "password789", region: "日本", isActive: false),
    ]

    @State private var showingAddSheet: Bool = false
    @State private var newAppleID: String = ""
    @State private var newPassword: String = ""
    @State private var newRegion: String = "中国"
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    var body: some View {
        NavigationView {
            List {
                if accounts.isEmpty {
                    Text("暂无已保存账号")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                } else {
                    Section("已保存账号") {
                        ForEach(accounts) { account in
                            accountRow(account)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteAccount(account)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("App Store 账号管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addAccountSheet
            }
            .overlay {
                if showToast {
                    Text(toastMessage)
                        .font(.subheadline)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation { showToast = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Account row

    private func accountRow(_ account: AppleAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: account.isActive ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.title2)
                .foregroundColor(account.isActive ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(account.appleID)
                        .font(.system(size: 15, weight: .medium))
                    if account.isActive {
                        Text("当前")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("密码: \(account.maskedPassword)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(account.region)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if !account.isActive {
                Button {
                    switchAccount(account)
                } label: {
                    Text("切换")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Add account sheet

    private var addAccountSheet: some View {
        NavigationView {
            Form {
                Section("添加账号") {
                    TextField("Apple ID", text: $newAppleID)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    SecureField("密码", text: $newPassword)
                    Picker("地区", selection: $newRegion) {
                        Text("中国").tag("中国")
                        Text("美国").tag("美国")
                        Text("日本").tag("日本")
                        Text("韩国").tag("韩国")
                        Text("香港").tag("香港")
                        Text("台湾").tag("台湾")
                    }
                }
            }
            .navigationTitle("添加账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        resetAddFields()
                        showingAddSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("添加") {
                        addAccount()
                    }
                    .disabled(newAppleID.isEmpty || newPassword.isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func addAccount() {
        let account = AppleAccount(
            appleID: newAppleID,
            password: newPassword,
            region: newRegion,
            isActive: false
        )
        accounts.append(account)
        resetAddFields()
        showingAddSheet = false
        showToast(message: "账号已添加")
    }

    private func deleteAccount(_ account: AppleAccount) {
        if account.isActive {
            showToast(message: "无法删除当前活跃账号")
            return
        }
        accounts.removeAll { $0.id == account.id }
        showToast(message: "账号已删除")
    }

    private func switchAccount(_ account: AppleAccount) {
        for i in accounts.indices {
            accounts[i].isActive = (accounts[i].id == account.id)
        }
        showToast(message: "已切换至 \(account.appleID)")
    }

    private func resetAddFields() {
        newAppleID = ""
        newPassword = ""
        newRegion = "中国"
    }

    private func showToast(message: String) {
        toastMessage = message
        withAnimation { showToast = true }
    }
}
