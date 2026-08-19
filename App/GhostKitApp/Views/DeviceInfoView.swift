//
//  DeviceInfoView.swift
//  GhostKit
//
//  Device information page: system version, device model, IDFA, IDFV, UDID.
//

import SwiftUI
import UIKit
import AdSupport
import Foundation

struct DeviceInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var udid: String = ""
    @State private var serialNumber: String = ""
    @State private var ecid: String = ""
    @State private var wifiMac: String = ""
    @State private var bluetoothMac: String = ""
    @State private var copiedField: String?

    var body: some View {
        NavigationView {
            List {
                Section("系统") {
                    infoRow(title: "iOS 版本", value: systemVersion, icon: "iphone")
                    infoRow(title: "设备型号", value: deviceModel, icon: "cpu")
                    infoRow(title: "设备名称", value: deviceName, icon: "tag")
                }

                Section("标识符") {
                    copyableRow(title: "IDFA", value: idfa, icon: "number.circle")
                    copyableRow(title: "IDFV", value: idfv, icon: "number.square")
                    copyableRow(title: "UDID", value: udid, icon: "barcode.viewfinder")
                }

                Section("硬件") {
                    copyableRow(title: "序列号", value: serialNumber, icon: "rectangle.dashed")
                    copyableRow(title: "ECID", value: ecid, icon: "qrcode")
                    copyableRow(title: "Wi-Fi MAC", value: wifiMac, icon: "wifi")
                    copyableRow(title: "蓝牙 MAC", value: bluetoothMac, icon: "antenna.radiowaves.left.and.right")
                }

                Section("存储") {
                    infoRow(title: "总容量", value: totalDiskSpace, icon: "internaldrive")
                    infoRow(title: "可用容量", value: freeDiskSpace, icon: "externaldrive")
                    infoRow(title: "电池电量", value: batteryLevel, icon: "battery.100")
                }
            }
            .navigationTitle("设备信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: loadDeviceInfo)
        }
    }

    // MARK: - Computed device properties

    private var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
        return modelName(for: machine) ?? machine
    }

    private var deviceName: String {
        UIDevice.current.name
    }

    private var idfa: String {
        ASIdentifierManager.shared().advertisingIdentifier.uuidString
    }

    private var idfv: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "不可用"
    }

    private var totalDiskSpace: String {
        format(bytes: totalDiskBytes())
    }

    private var freeDiskSpace: String {
        format(bytes: freeDiskBytes())
    }

    private var batteryLevel: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "未知" }
        return "\(Int(level * 100))%"
    }

    // MARK: - Rows

    private func infoRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 26)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func copyableRow(title: String, value: String, icon: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            withAnimation { copiedField = title }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copiedField = nil }
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading) {
                    Text(title)
                    Text(value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if copiedField == title {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func loadDeviceInfo() {
        // UDID - read via private API fallback chain.
        udid = readUDID() ?? "不可用"
        serialNumber = readSerialNumber() ?? "不可用"
        ecid = readECID() ?? "不可用"
        wifiMac = readMACAddress(forInterface: "en0") ?? "不可用"
        bluetoothMac = readMACAddress(forInterface: "en1") ?? "不可用"
    }

    // MARK: - Private helpers

    /// Resolve the device model marketing name from the machine identifier.
    private func modelName(for machine: String) -> String? {
        let mapping: [String: String] = [
            "iPhone14,5":  "iPhone 13",
            "iPhone14,6":  "iPhone SE (3rd gen)",
            "iPhone14,7":  "iPhone 14",
            "iPhone14,8":  "iPhone 14 Plus",
            "iPhone15,2":  "iPhone 14 Pro",
            "iPhone15,3":  "iPhone 14 Pro Max",
            "iPhone15,4":  "iPhone 15",
            "iPhone15,5":  "iPhone 15 Plus",
            "iPhone16,1":  "iPhone 15 Pro",
            "iPhone16,2":  "iPhone 15 Pro Max",
            "iPad13,1":    "iPad Air (4th gen)",
            "iPad14,1":    "iPad (10th gen)",
            "iPad14,2":    "iPad (10th gen)",
        ]
        return mapping[machine]
    }

    /// Read UDID via the MobileGestalt private framework.
    private func readUDID() -> String? {
        // MobileGestalt's MGCopyAnswer for "UniqueDeviceIDData".
        let MGCopyAnswer = NSClassFromString("MobileGestalt") as? NSObject.Type
        let selector = NSSelectorFromString("MGCopyAnswer:")
        guard let cls = MGCopyAnswer, cls.responds(to: selector) else {
            return UIDevice.current.identifierForVendor?.uuidString
        }
        let udidKey = "UniqueDeviceIDData" as CFString
        if let result = cls.perform(selector, with: udidKey)?.takeUnretainedValue() {
            if let str = result as? String { return str }
            if let data = result as? Data {
                return data.map { String(format: "%02x", $0) }.joined()
            }
        }
        return UIDevice.current.identifierForVendor?.uuidString
    }

    private func readSerialNumber() -> String? {
        let MGCopyAnswer = NSClassFromString("MobileGestalt") as? NSObject.Type
        let selector = NSSelectorFromString("MGCopyAnswer:")
        guard let cls = MGCopyAnswer, cls.responds(to: selector) else { return nil }
        let key = "SerialNumber" as CFString
        if let result = cls.perform(selector, with: key)?.takeUnretainedValue() as? String {
            return result
        }
        return nil
    }

    private func readECID() -> String? {
        let MGCopyAnswer = NSClassFromString("MobileGestalt") as? NSObject.Type
        let selector = NSSelectorFromString("MGCopyAnswer:")
        guard let cls = MGCopyAnswer, cls.responds(to: selector) else { return nil }
        let key = "UniqueChipID" as CFString
        if let result = cls.perform(selector, with: key)?.takeUnretainedValue() {
            if let num = result as? NSNumber { return String(format: "%llX", num.int64Value) }
        }
        return nil
    }

    /// Read the MAC address for a given network interface via getifaddrs.
    private func readMACAddress(forInterface name: String) -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(firstAddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            let interface = cur.pointee
            let ifaName = String(cString: interface.ifa_name)
            if ifaName == name,
               let addr = interface.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_LINK) {
                // sa_family == AF_LINK -> sockaddr_dl
                let dlAddr = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_dl.self)
                let lladdr = dlAddr.withMemoryRebound(to: UInt8.self, capacity: Int(dlAddr.pointee.sdl_alen)) { p in
                    let offset = Int(dlAddr.pointee.sdl_nlen)
                    let len = Int(dlAddr.pointee.sdl_alen)
                    return Array(UnsafeBufferPointer(start: p.advanced(by: offset), count: len))
                }
                if lladdr.count == 6 {
                    return lladdr.map { String(format: "%02X", $0) }.joined(separator: ":")
                }
            }
            ptr = interface.ifa_next
        }
        return nil
    }

    // MARK: - Disk space

    private func totalDiskBytes() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
        } catch { return 0 }
    }

    private func freeDiskBytes() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        } catch { return 0 }
    }

    private func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
