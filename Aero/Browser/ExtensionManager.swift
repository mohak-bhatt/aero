import AppKit
import Combine
import WebKit

struct InstalledExtension: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    let path: String
    let context: WKWebExtensionContext
}

struct AvailableExtension: Identifiable {
    var id: String { appex.path }
    let name: String
    let appName: String
    let appex: URL
}

struct ExtensionPopup {
    let name: String
    let webView: WKWebView
}

/// Loads WebKit web extensions (the same format Safari uses) from a folder, .appex or .app.
@MainActor
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    static let shared = ExtensionManager()

    let controller: WKWebExtensionController
    @Published private(set) var items: [InstalledExtension] = []
    @Published var popup: ExtensionPopup?
    @Published private(set) var available: [AvailableExtension] = []
    private var installingPaths = Set<String>()
    private var restoring = false
    private let key = "aero.extensions.v1"

    private override init() {
        controller = WKWebExtensionController(configuration: .default())
        super.init()
        controller.delegate = self
        Task { await restore() }
    }

    // MARK: Install / remove

    func install(from url: URL) async {
        guard !items.contains(where: { $0.path == url.path }), installingPaths.insert(url.path).inserted else { return }
        defer { installingPaths.remove(url.path) }
        do {
            let webExtension: WKWebExtension
            switch url.pathExtension.lowercased() {
            case "appex":
                guard let bundle = Bundle(url: url) else { throw CocoaError(.fileReadCorruptFile) }
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            case "app":
                let plugIns = url.appendingPathComponent("Contents/PlugIns")
                let appex = try FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)
                    .first { $0.pathExtension == "appex" }
                guard let appex, let bundle = Bundle(url: appex) else { throw CocoaError(.fileNoSuchFile) }
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            default:
                webExtension = try await WKWebExtension(resourceBaseURL: url)
            }
            // Consent precedes loading background scripts or granting any scope.
            let permissions = webExtension.requestedPermissions.map { $0.rawValue }.sorted()
            let sites = webExtension.requestedPermissionMatchPatterns.map { $0.string }.sorted()
            let alert = NSAlert()
            alert.messageText = "Allow \(webExtension.displayName ?? "extension")?"
            alert.informativeText = "Only install extensions you trust. Local extension code can change between launches.\n\nPermissions:\n"
                + (permissions.isEmpty ? "None" : permissions.joined(separator: "\n"))
                + "\n\nWebsite access:\n" + (sites.isEmpty ? "None" : sites.joined(separator: "\n"))
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Allow and Load")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            let context = WKWebExtensionContext(for: webExtension)
            for permission in webExtension.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
            for pattern in webExtension.requestedPermissionMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
            try controller.load(context)
            items.append(InstalledExtension(name: webExtension.displayName ?? url.deletingPathExtension().lastPathComponent,
                                            version: webExtension.displayVersion ?? "", path: url.path, context: context))
            persist()
            scanAvailable()
        } catch {
            Prompt.info(title: "Couldn't add extension", message: error.localizedDescription)
        }
    }

    /// Safari web extensions installed from the App Store live inside apps; find them without any file picker.
    func scanAvailable() {
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        var found: [AvailableExtension] = []
        for root in ["/Applications", home + "/Applications"] {
            guard let apps = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let plugIns = URL(fileURLWithPath: root).appendingPathComponent(app).appendingPathComponent("Contents/PlugIns")
                guard let appexes = try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil) else { continue }
                for appex in appexes where appex.pathExtension == "appex" {
                    guard let info = Bundle(url: appex)?.infoDictionary,
                          let ext = info["NSExtension"] as? [String: Any],
                          ext["NSExtensionPointIdentifier"] as? String == "com.apple.Safari.web-extension" else { continue }
                    let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? appex.deletingPathExtension().lastPathComponent
                    found.append(AvailableExtension(name: name, appName: String(app.dropLast(4)), appex: appex))
                }
            }
        }
        available = found.filter { candidate in !items.contains { $0.path == candidate.appex.path } }
    }

    func openExtensionStore() {
        if let url = URL(string: "macappstore://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?q=safari%20extensions&media=software") {
            NSWorkspace.shared.open(url)
        }
    }

    func remove(_ item: InstalledExtension) {
        do { try controller.unload(item.context) }
        catch {
            Prompt.info(title: "Couldn't remove extension", message: error.localizedDescription)
            return
        }
        items.removeAll { $0.id == item.id }
        persist()
    }

    func perform(_ item: InstalledExtension) { item.context.performAction(for: nil) }

    func chooseAndInstall() {
        let panel = NSOpenPanel()
        panel.message = "Choose an extension folder (with manifest.json), a Safari extension (.appex) or an app that contains one."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await install(from: url) }
    }

    private func persist() {
        guard !restoring else { return }
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }

    private func restore() async {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        restoring = true
        defer { restoring = false; persist() }
        for path in paths {
            await install(from: URL(fileURLWithPath: path))
        }
    }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController,
                                presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        if let webView = action.popupWebView {
            popup = ExtensionPopup(name: context.webExtension.displayName ?? "Extension", webView: webView)
        }
        completionHandler(nil)
    }
}
