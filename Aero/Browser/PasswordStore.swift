//
//  Credential.swift
//  Aero
//
//  Created by Mohak Bhatt on 25/10/26.
//


import AppKit
import Combine
import LocalAuthentication
import Security
import WebKit

struct Credential: Identifiable, Hashable {
    let host: String
    let username: String
    var id: String { host + "|" + username }
}

struct PendingCredential: Equatable {
    let host: String
    let username: String
    let password: String
}

/// Passwords live in the macOS Keychain; this class only holds host/username for display.
@MainActor
final class PasswordStore: ObservableObject {
    static let shared = PasswordStore()
    @Published private(set) var credentials: [Credential] = []
    @Published var pending: PendingCredential?
    private let neverKey = "aero.passwords.never"
    private let label = "Aero"

    private init() { reload() }

    // MARK: Keychain

    func reload() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { credentials = []; return }
        credentials = items.compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String,
                  let user = item[kSecAttrAccount as String] as? String else { return nil }
            return Credential(host: host, username: user)
        }
        .sorted { ($0.host, $0.username) < ($1.host, $1.username) }
    }

    func save(host: String, username: String, password: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username,
            kSecAttrLabel as String: label
        ]
        let data = Data(password.utf8)
        if SecItemCopyMatching(base as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var item = base
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
        reload()
    }

    func password(host: String, username: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username,
            kSecAttrLabel as String: label,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ credential: Credential) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.host,
            kSecAttrAccount as String: credential.username,
            kSecAttrLabel as String: label
        ]
        SecItemDelete(query as CFDictionary)
        reload()
    }

    func credentials(for host: String) -> [Credential] {
        credentials.filter { PasswordOriginPolicy.matchesCredential(requestHost: host, credentialHost: $0.host) }
    }

    // MARK: Save prompt

    func offerToSave(host: String, username: String, password: String) {
        guard !neverHosts.contains(host) else { return }
        if let existing = self.password(host: host, username: username), existing == password { return }
        pending = PendingCredential(host: host, username: username, password: password)
    }

    func confirmPending() {
        guard let pending else { return }
        save(host: pending.host, username: pending.username, password: pending.password)
        self.pending = nil
    }

    func neverSave(_ host: String) {
        UserDefaults.standard.set(Array(neverHosts.union([host])), forKey: neverKey)
        pending = nil
    }

    private var neverHosts: Set<String> { Set(UserDefaults.standard.stringArray(forKey: neverKey) ?? []) }

    // MARK: Authentication (Touch ID / password) before showing a password

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    // MARK: CSV import (Chrome, Safari, Firefox, Edge, Brave, 1Password, Bitwarden exports)

    func importCSV(_ url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let rows = Self.parseCSV(text)
        guard let header = rows.first?.map({ $0.lowercased() }) else { return 0 }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let urlColumn = column(["url", "login_uri", "website", "web site"]),
              let userColumn = column(["username", "login_username", "user", "login"]),
              let passColumn = column(["password", "login_password"]) else { return 0 }
        var count = 0
        for row in rows.dropFirst() where row.count > max(urlColumn, userColumn, passColumn) {
            let host = URL(string: row[urlColumn])?.host ?? row[urlColumn]
            guard !host.isEmpty, !row[passColumn].isEmpty else { continue }
            save(host: host, username: row[userColumn], password: row[passColumn])
            count += 1
        }
        return count
    }

    nonisolated static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 } else { quoted = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.append(c)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    nonisolated static func js(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let string = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(string.dropFirst().dropLast())
    }
}

final class PasswordMessageHandler: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    init(tab: BrowserTab) { self.tab = tab }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        tab?.handlePassword(message)
    }
}

enum PasswordScript {
    static let world = WKContentWorld.world(name: "Aero.Passwords")
    static let source = """
    (function () {
      if (window.__aeroPass) return;
      function post(msg) { try { window.webkit.messageHandlers.aeroPass.postMessage(msg); } catch (e) {} }
      function pwFields() {
        return Array.prototype.slice.call(document.querySelectorAll('input[type=password]'))
          .filter(function (i) { return i.offsetParent !== null; });
      }
      function userFieldFor(pw) {
        var scope = pw.form || document;
        var inputs = scope.querySelectorAll('input:not([type=password]):not([type=hidden]):not([type=submit]):not([type=button]):not([type=checkbox]):not([type=radio])');
        var best = null;
        for (var i = 0; i < inputs.length; i++) {
          if (inputs[i].compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING) best = inputs[i];
        }
        return best;
      }
      function setValue(el, v) {
        var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        setter.call(el, v);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
      window.__aeroPass = {
        fill: function (user, pass, expectedURL) {
          if (location.href !== expectedURL || location.protocol !== 'https:') return;
          var pws = pwFields(); if (!pws.length) return;
          var u = userFieldFor(pws[0]);
          if (u && user) setValue(u, user);
          setValue(pws[0], pass);
        }
      };
      var asked = false;
      function ask() { if (asked) return; if (pwFields().length) { asked = true; post({ type: 'lookup', host: location.hostname }); } }
      function capture() {
        var pws = pwFields();
        for (var i = 0; i < pws.length; i++) {
          if (pws[i].value) {
            var u = userFieldFor(pws[i]);
            post({ type: 'submit', host: location.hostname, username: u ? u.value : '', password: pws[i].value });
            return;
          }
        }
      }
      document.addEventListener('submit', function (e) { if (e.isTrusted) capture(); }, true);
      document.addEventListener('click', function (e) {
        var t = e.target.closest && e.target.closest('button, input[type=submit]');
        if (e.isTrusted && t) capture();
      }, true);
      new MutationObserver(ask).observe(document.documentElement, { childList: true, subtree: true });
      ask();
    })();
    """
}