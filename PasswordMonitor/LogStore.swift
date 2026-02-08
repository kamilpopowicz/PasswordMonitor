import Foundation
import AppKit
import Darwin
import Combine
import UniformTypeIdentifiers
import PasswordMonitorCore

/// Stores log file content and keeps it updated while the file changes.
@MainActor
final class LogStore: ObservableObject {
    @Published var content: String = ""

    private let fileURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    init(fileURL: URL = Logger.shared.fileURL) {
        self.fileURL = fileURL
        ensureFileExists()
        load()
        startMonitoring()
    }

    func start() {
        startMonitoring()
    }

    func stop() {
        stopMonitoring()
    }

    func reload() {
        load()
    }

    func clear() {
        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
            load()
        } catch {
            Logger.shared.logLocalized("log_logstore_clear_failed %@", String(describing: error))
        }
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    func exportLog(content: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.log]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        panel.nameFieldStringValue = "password-monitor-\(timestamp).log"
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Logger.shared.logLocalized("log_logstore_export_failed %@", String(describing: error))
            }
        }
    }
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func load() {
        content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    private func startMonitoring() {
        stopMonitoring()

        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        self.source = source

        source.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor != -1 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        source.resume()
    }

    private func stopMonitoring() {
        source?.cancel()
        source = nil
    }

    private func handleFileEvent() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            ensureFileExists()
            startMonitoring()
            return
        }
        load()
    }
}
