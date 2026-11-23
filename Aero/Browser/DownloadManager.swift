import AppKit
import Combine
import Security
import WebKit

@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    enum State: Equatable { case running, finished, failed(String) }

    let id = UUID()
    let filename: String
    let destination: URL
    @Published var progress: Double = 0
    @Published var state: State = .running

    private var download: WKDownload?
    var onCancel: (() -> Void)?
    private var cancellable: AnyCancellable?

    init(destination: URL) {
        self.destination = destination
        self.filename = destination.lastPathComponent
    }

    func observe(_ download: WKDownload) {
        self.download = download
        cancellable = download.progress.publisher(for: \.fractionCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.progress = $0 }
    }

    func cancel() {
        guard state == .running else { return }
        state = .failed("Cancelled")
        download?.cancel { [weak self] _ in
            Task { @MainActor in self?.onCancel?(); self?.releaseDownload() }
        }
    }

    func releaseDownload() {
        cancellable = nil
        download = nil
        onCancel = nil
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    private var byDownload: [ObjectIdentifier: DownloadItem] = [:]
    private var itemChanges: [UUID: AnyCancellable] = [:]
    private var reservedDestinations: Set<URL> = []

    private func reserve(in folder: URL, filename: String) -> URL {
        let url = Self.uniqueURL(in: folder, filename: filename, excluding: reservedDestinations)
        reservedDestinations.insert(url)
        return url
    }

    var activeItems: [DownloadItem] { items.filter { $0.state == .running } }

    var downloadsFolder: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private static func hasEntitlement(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return (SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? Bool) == true
    }

    private static var warned = false

    /// ~/Downloads when writable; a save panel only if the entitlement allows it (otherwise the
    /// system would crash the app); last resort is a temporary folder plus a one-time explanation.
    func chooseDestination(filename: String) async -> URL? {
        let filename = Self.safeFilename(filename)
        if let folder = downloadsFolder, FileManager.default.isWritableFile(atPath: folder.path) {
            return reserve(in: folder, filename: filename)
        }
        if Self.hasEntitlement("com.apple.security.files.user-selected.read-write") {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.directoryURL = downloadsFolder
            guard await panel.begin() == .OK, let url = panel.url else { return nil }
            try? FileManager.default.removeItem(at: url)
            return url
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("AeroDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        if !Self.warned {
            Self.warned = true
            Prompt.info(title: "Downloads need permission",
                        message: "In Xcode: Signing & Capabilities → App Sandbox → File Access, set Downloads Folder and User Selected File to Read/Write. Until then files are saved in a temporary folder.")
        }
        return reserve(in: temp, filename: filename)
    }

    func begin(destination: URL, download: WKDownload) {
        let item = DownloadItem(destination: destination)
        itemChanges[item.id] = item.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        item.observe(download)
        let identifier = ObjectIdentifier(download)
        item.onCancel = { [weak self, weak item] in
            self?.byDownload.removeValue(forKey: identifier)
            if let item { self?.reservedDestinations.remove(item.destination) }
        }
        byDownload[ObjectIdentifier(download)] = item
        items.insert(item, at: 0)
    }

    func finish(_ download: WKDownload) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        reservedDestinations.remove(item.destination)
        item.progress = 1
        item.state = .finished
        item.releaseDownload()
    }

    func fail(_ download: WKDownload, error: Error) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        reservedDestinations.remove(item.destination)
        if item.state == .running { item.state = .failed(error.localizedDescription) }
        item.releaseDownload()
    }

    func clearFinished() {
        for item in items where item.state != .running { itemChanges.removeValue(forKey: item.id) }
        items.removeAll { $0.state != .running }
    }

    func showInFinder(_ item: DownloadItem? = nil) {
        if let url = item?.destination ?? items.first(where: { $0.state == .finished })?.destination {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let folder = downloadsFolder {
            NSWorkspace.shared.open(folder)
        }
    }

    static func safeFilename(_ proposed: String) -> String {
        let leaf = (proposed.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        let cleaned = leaf.components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "Download" : cleaned
    }

    static func uniqueURL(in folder: URL, filename: String, excluding reserved: Set<URL> = []) -> URL {
        let filename = safeFilename(filename)
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var counter = 1
        while reserved.contains(candidate) || FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }
}

// MARK: - Downloads

extension DownloadManager: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let manager = DownloadManager.shared
        guard let destination = await manager.chooseDestination(filename: suggestedFilename) else {
            return nil // user cancelled the save panel
        }
        manager.begin(destination: destination, download: download)
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        DownloadManager.shared.finish(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        DownloadManager.shared.fail(download, error: error)
    }
}
