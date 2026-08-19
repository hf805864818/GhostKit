//
//  AccountListView.swift
//  GhostKit
//
//  App Store account management page.
//  Lists saved Apple ID accounts, allows adding, deleting and switching.
//  Accounts are persisted to a JSON file and the currently logged-in
//  Apple ID is detected from the system.
//

import SwiftUI
import Foundation

// MARK: - Account model

struct AppleAccount: Identifiable, Hashable, Codable {
    let id: UUID
    let appleID: String
    let password: String
    let region: String
    var isActive: Bool

    init(appleID: String, password: String, region: String, isActive: Bool) {
        self.id = UUID()
        self.appleID = appleID
        self.password = password
        self.region = region
        self.isActive = isActive
    }

    var maskedPassword: String {
        String(repeating: "*", count: max(password.count, 4))
    }
}

// MARK: - Account persistence manager

final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published var accounts: [AppleAccount] = []
    @Published var systemAppleID: String?

    private let fileURL: URL

    private init() {
        // Store accounts in the app's documents directory
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = docsDir.appendingPathComponent("ghostkit_accounts.json")
        loadAccounts()
        detectSystemAppleID()
    }

    // MARK: - Persistence

    func loadAccounts() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        accounts = (try? JSONDecoder().decode([AppleAccount].self, from: data)) ?? []
    }

    func saveAccounts() {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save accounts: \(error)")
        }
    }

    // MARK: - CRUD

    func add(_ account: AppleAccount) {
        accounts.append(account)
        saveAccounts()
    }

    func delete(_ account: AppleAccount) {
        accounts.removeAll { $0.id == account.id }
        saveAccounts()
    }

    func switchTo(_ account: AppleAccount) {
        for i in accounts.indices {
            accounts[i].isActive = (accounts[i].id == account.id)
        }
        saveAccounts()
    }

    // MARK: - Detect current Apple ID from system

    func detectSystemAppleID() {
        // Method 1: Read from App Store preferences plist.
        // com.apple.AppStore.plist contains the "AppleID" key for the
        // currently signed-in App Store account.  This is distinct from
        // the iCloud account stored in MobileMeAccounts.plist.
        let appStorePrefsPath = "/var/mobile/Library/Preferences/com.apple.AppStore.plist"
        if let dict = NSDictionary(contentsOfFile: appStorePrefsPath) {
            if let appleID = dict["AppleID"] as? String, !appleID.isEmpty {
                systemAppleID = appleID
                return
            }
            // Some iOS versions use "SignedInAppleID" instead.
            if let signedInID = dict["SignedInAppleID"] as? String, !signedInID.isEmpty {
                systemAppleID = signedInID
                return
            }
        }

        // Method 2: Read from the accounts plist as a fallback.
        // com.apple.accounts.plist may contain iTunes/App Store accounts.
        let accountsPrefsPath = "/var/mobile/Library/Preferences/com.apple.accounts.plist"
        if let dict = NSDictionary(contentsOfFile: accountsPrefsPath) {
            if let accounts = dict["Accounts"] as? [String: [String: Any]] {
                for (_, info) in accounts {
                    let accountType = info["AccountType"] as? String ?? ""
                    if accountType == "iTunesStore" || accountType.contains("AppleID") {
                        if let appleID = info["AccountID"] as? String ??
                                         info["AppleID"] as? String,
                           !appleID.isEmpty {
                            systemAppleID = appleID
                            return
                        }
                    }
                }
            }
        }

        // Method 3: Read from MobileMeAccounts.plist (iCloud account).
        // This is the iCloud Apple ID which may differ from the App Store ID.
        let mobileMePath = "/var/mobile/Library/Preferences/MobileMeAccounts.plist"
        if let dict = NSDictionary(contentsOfFile: mobileMePath) {
            if let accountsArray = dict["Accounts"] as? [[String: Any]] {
                for accountDict in accountsArray {
                    if let accountID = accountDict["AccountID"] as? String,
                       let isPrimary = accountDict["IsPrimaryAccount"] as? Bool, isPrimary {
                        systemAppleID = accountID
                        return
                    }
                }
                if let first = accountsArray.first,
                   let accountID = first["AccountID"] as? String {
                    systemAppleID = accountID
                    return
                }
            }
        }

        // Method 4: Try reading from keychain.
        // Apple ID tokens are stored as generic passwords under the
        // "com.apple.account" access group, not as internet passwords.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.apple.account.AppleID",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let dict = result as? [String: Any],
           let account = dict[kSecAttrAccount as String] as? String,
           !account.isEmpty {
            systemAppleID = account
            return
        }

        systemAppleID = nil
    }

    /// Refresh the system Apple ID detection.
    func refreshSystemAccount() {
        detectSystemAppleID()
    }
}

// MARK: - AccountListView

struct AccountListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AccountStore.shared

    @State private var showingAddSheet: Bool = false
    @State private var newAppleID: String = ""
    @State private var newPassword: String = ""
    @State private var newRegion: String = "中国"
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    var body: some View {
        NavigationView {
            List {
                // System account section
                Section("当前设备登录") {
                    if let appleID = store.systemAppleID {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appleID)
                                    .font(.system(size: 15, weight: .medium))
                                Text("系统当前登录的 Apple ID")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("系统")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("未检测到已登录的 Apple ID")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                store.refreshSystemAccount()
                                showToast(message: store.systemAppleID != nil
                                          ? "检测到: \(store.systemAppleID!)"
                                          : "仍未检测到 Apple ID")
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Saved accounts section
                Section("已保存账号") {
                    if store.accounts.isEmpty {
                        Text("暂无已保存账号，点击右上角 + 添加")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(store.accounts) { account in
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
                        .textInputAutocapitalization(.never)
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
        store.add(account)
        resetAddFields()
        showingAddSheet = false
        showToast(message: "账号已添加")
    }

    private func deleteAccount(_ account: AppleAccount) {
        if account.isActive {
            showToast(message: "无法删除当前活跃账号")
            return
        }
        store.delete(account)
        showToast(message: "账号已删除")
    }

    private func switchAccount(_ account: AppleAccount) {
        store.switchTo(account)
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
