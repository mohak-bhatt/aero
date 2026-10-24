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

    private weak var download: WKDownload?
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
        download?.cancel { _ in }
        state = .failed("Cancelled")
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    private var byDownload: [ObjectIdentifier: DownloadItem] = [:]

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
        if let folder = downloadsFolder, FileManager.default.isWritableFile(atPath: folder.path) {
            return Self.uniqueURL(in: folder, filename: filename)
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
        return Self.uniqueURL(in: temp, filename: filename)
    }

    func begin(destination: URL, download: WKDownload) {
        let item = DownloadItem(destination: destination)
        item.observe(download)
        byDownload[ObjectIdentifier(download)] = item
        items.insert(item, at: 0)
    }

    func finish(_ download: WKDownload) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.progress = 1
        item.state = .finished
    }

    func fail(_ download: WKDownload, error: Error) {
        guard let item = byDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if item.state == .running { item.state = .failed(error.localizedDescription) }
    }

    func clearFinished() {
        items.removeAll { $0.state != .running }
    }

    func showInFinder(_ item: DownloadItem? = nil) {
        if let url = item?.destination ?? items.first(where: { $0.state == .finished })?.destination {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let folder = downloadsFolder {
            NSWorkspace.shared.open(folder)
        }
    }

    private static func uniqueURL(in folder: URL, filename: String) -> URL {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }
}
