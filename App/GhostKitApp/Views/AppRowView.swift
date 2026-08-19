//
//  AppRowView.swift
//  GhostKit
//
//  A single row in the installed-applications list.
//  Displays the app icon, display name, version and bundle identifier.
//

import SwiftUI

struct AppRowView: View {
    let app: AppInfo

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 56, height: 56)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if app.isSystemApp {
                        Text("系统")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                }

                Text(app.bundleIdentifier)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("v\(app.shortVersion.isEmpty ? app.version : app.shortVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var iconView: some View {
        if let icon = app.icon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}
