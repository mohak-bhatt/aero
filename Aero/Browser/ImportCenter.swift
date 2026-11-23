//
//  DetectedBrowser.swift
//  Aero
//
//  Created by Mohak Bhatt on 05/11/26.
//


import AppKit
import CommonCrypto
import Combine
import Security
import SQLite3
import SwiftUI

struct DetectedBrowser: Identifiable, Hashable {
    enum Kind { case chromium, firefox, safari }
    let id: String
    let name: String
    let kind: Kind
    let profile: URL
    var keychainService: String? = nil
    var keychainAccount: String? = nil
    var readable = true

    var symbol: String {
        switch kind { case .safari: return "safari"; case .firefox: return "flame"; case .chromium: return "globe" }
    }
    var canImportPasswords: Bool { kind == .chromium }
}

/// Finds the browsers installed on this Mac and imports straight from their profiles — no file picker.
@MainActor
final class ImportCenter: ObservableObject {
    @Published var browsers: [DetectedBrowser] = []
    @Published var selected: String?
    @Published var bookmarks = true
    @Published var history = true
    @Published var passwords = true
    @Published var status = ""
    @Published var working = false

    private let home = String(cString: getpwuid(getuid()).pointee.pw_dir)

    var needsFullDiskAccess: Bool { browsers.contains { $0.kind == .safari && !$0.readable } }

    func detect() {
        let support = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support")
        var found: [DetectedBrowser] = []
        let chromium: [(String, String, String)] = [
            ("Google Chrome", "Google/Chrome", "Chrome"), ("Arc", "Arc/User Data", "Arc"),
            ("Brave", "BraveSoftware/Brave-Browser", "Brave"), ("Microsoft Edge", "Microsoft Edge", "Microsoft Edge"),
            ("Vivaldi", "Vivaldi", "Vivaldi"), ("Opera", "com.operasoftware.Opera", "Opera"), ("Chromium", "Chromium", "Chromium")
        ]
        for (name, path, account) in chromium {
            let base = support.appendingPathComponent(path)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base.path) else { continue }
            var profiles = entries.filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted().map { base.appendingPathComponent($0) }
            if name == "Opera" { profiles = [base] }
            for profile in profiles where FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path) {
                let suffix = profiles.count > 1 ? " (\(profile.lastPathComponent))" : ""
                found.append(DetectedBrowser(id: profile.path, name: name + suffix, kind: .chromium, profile: profile,
                                             keychainService: "\(account) Safe Storage", keychainAccount: account))
            }
        }
        let firefoxProfiles = support.appendingPathComponent("Firefox/Profiles")
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: firefoxProfiles.path)) ?? [] {
            let profile = firefoxProfiles.appendingPathComponent(entry)
            if FileManager.default.fileExists(atPath: profile.appendingPathComponent("places.sqlite").path) {
                found.append(DetectedBrowser(id: profile.path, name: "Firefox", kind: .firefox, profile: profile))
            }
        }
        let safari = URL(fileURLWithPath: home).appendingPathComponent("Library/Safari")
        if FileManager.default.fileExists(atPath: safari.path) {
            found.append(DetectedBrowser(id: safari.path, name: "Safari", kind: .safari, profile: safari,
                                         readable: FileManager.default.isReadableFile(atPath: safari.appendingPathComponent("Bookmarks.plist").path)))
        }
        browsers = found
        if selected == nil || !found.contains(where: { $0.id == selected }) { selected = found.first?.id }
    }

    func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }

    func run() {
        guard let browser = browsers.first(where: { $0.id == selected }) else { return }
        working = true
        defer { working = false }
        var parts: [String] = []

        if bookmarks {
            var nodes: [BookmarkNode] = []
            switch browser.kind {
            case .chromium: nodes = (try? Data(contentsOf: browser.profile.appendingPathComponent("Bookmarks"))).map(Importer.parseChromium) ?? []
            case .firefox: nodes = Importer.readFirefoxBookmarks(at: copy(browser.profile.appendingPathComponent("places.sqlite")) ?? "")
            case .safari: nodes = (try? Data(contentsOf: browser.profile.appendingPathComponent("Bookmarks.plist"))).map(Importer.parseSafari) ?? []
            }
            let count = BookmarkStore.flatten(nodes).count
            if count > 0 {
                BookmarkStore.shared.addNode(BookmarkNode(title: "Imported from \(browser.name)", url: nil, iconPNG: nil, children: nodes))
                parts.append("\(count) bookmarks")
            }
        }
        if history {
            let file: String
            switch browser.kind { case .chromium: file = "History"; case .firefox: file = "places.sqlite"; case .safari: file = "History.db" }
            if let path = copy(browser.profile.appendingPathComponent(file)) {
                let entries = Importer.readHistory(at: path)
                HistoryStore.shared.importEntries(entries)
                if !entries.isEmpty { parts.append("\(entries.count) history items") }
            }
        }
        if passwords, browser.canImportPasswords {
            let count = importChromiumPasswords(browser)
            if count > 0 { parts.append("\(count) passwords") }
        }
        status = parts.isEmpty ? "Nothing could be imported from \(browser.name)." : "Imported " + parts.joined(separator: ", ") + " from \(browser.name)."
    }

    // MARK: Helpers

    private func copy(_ url: URL) -> String? {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("aero-import-\(UUID().uuidString).db")
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return nil }
        return target.path
    }

    /// Chromium-family browsers encrypt saved passwords with a key kept in the Keychain
    /// (“Chrome Safe Storage” etc.). macOS asks you to allow Aero to read it, then passwords are re-saved in Aero.
    private func importChromiumPasswords(_ browser: DetectedBrowser) -> Int {
        guard let service = browser.keychainService, let account = browser.keychainAccount,
              let key = Self.safeStorageKey(service: service, account: account),
              let path = copy(browser.profile.appendingPathComponent("Login Data")) else { return 0 }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return 0 }
        defer { sqlite3_close(db); try? FileManager.default.removeItem(atPath: path) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT origin_url, username_value, password_value FROM logins WHERE blacklisted_by_user = 0", -1, &statement, nil) == SQLITE_OK else { return 0 }
        var count = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let originText = sqlite3_column_text(statement, 0), let host = URL(string: String(cString: originText))?.host else { continue }
            let user = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let length = Int(sqlite3_column_bytes(statement, 2))
            guard length > 3, let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let blob = Data(bytes: bytes, count: length)
            if let password = Self.decrypt(blob, key: key), !password.isEmpty {
                PasswordStore.shared.save(host: host, username: user, password: password)
                count += 1
            }
        }
        return count
    }

    nonisolated static func safeStorageKey(service: String, account: String) -> [UInt8]? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let secret = result as? Data else { return nil }
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let status = secret.withUnsafeBytes { raw -> Int32 in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), raw.bindMemory(to: Int8.self).baseAddress, secret.count,
                                 salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        return status == Int32(kCCSuccess) ? key : nil
    }

    nonisolated static func decrypt(_ blob: Data, key: [UInt8]) -> String? {
        guard blob.prefix(3) == Data("v10".utf8) else { return nil }
        let cipher = [UInt8](blob.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: 16)
        var output = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, cipher, cipher.count, &output, output.count, &moved)
        return status == Int32(kCCSuccess) ? String(bytes: output.prefix(moved), encoding: .utf8) : nil
    }
}

/// One-click import: pick a detected browser, tick what to bring over, press Import.
struct ImportView: View {
    @StateObject private var center = ImportCenter()
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if center.browsers.isEmpty {
                Text("No other browsers were found on this Mac.").foregroundStyle(.secondary)
                Text("If Aero is running sandboxed it can't see them — use File → More Import Options instead.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(center.browsers) { browser in
                    Button { center.selected = browser.id } label: {
                        HStack(spacing: 10) {
                            Image(systemName: browser.symbol).frame(width: 22)
                            Text(browser.name).font(.system(size: 13, weight: .medium))
                            Spacer()
                            if center.selected == browser.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                        }
                        .padding(.horizontal, 14).frame(height: 40)
                        .glass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RubberButtonStyle())
                }
                let current = center.browsers.first { $0.id == center.selected }
                HStack(spacing: 18) {
                    Toggle("Bookmarks", isOn: $center.bookmarks)
                    Toggle("History", isOn: $center.history)
                    Toggle("Passwords", isOn: $center.passwords).disabled(!(current?.canImportPasswords ?? false))
                }
                .toggleStyle(.checkbox)
                if let current, !current.canImportPasswords {
                    Text("\(current.name) keeps passwords in a form Aero can't read — export a CSV from it and use File → More Import Options.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if center.needsFullDiskAccess {
                    HStack {
                        Text("Safari data needs Full Disk Access.").font(.caption).foregroundStyle(.secondary)
                        Button("Open Settings") { center.openFullDiskAccess() }.controlSize(.small)
                    }
                }
                HStack {
                    Button("Import") { center.run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(center.working || center.selected == nil)
                    Text(center.status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: compact ? .infinity : 420, alignment: .leading)
        .onAppear { center.detect() }
    }
}

@MainActor
enum ImportWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.title = "Import"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 14) {
                Text("Import from another browser").font(.system(size: 20, weight: .semibold, design: .rounded))
                ImportView()
                Spacer(minLength: 0)
            }.padding(28).background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea()))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}