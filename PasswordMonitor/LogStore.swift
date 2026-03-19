//
//  LogStore.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 09/02/2026.
//

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
    @Published var isLoading: Bool = false

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
        isLoading = true
        let url = fileURL
        Task { [weak self] in
            let text = await LogStore.readFile(url: url)
            guard let self else { return }
            self.content = text
            self.isLoading = false
        }
    }

    private static func readFile(url: URL) async -> String {
        await Task.detached {
            (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }.value
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
