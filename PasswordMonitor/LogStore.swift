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
    enum RefreshMode: String, CaseIterable, Identifiable {
        case immediate
        case oneMinute
        case fiveMinutes

        var id: String { rawValue }

        var interval: TimeInterval? {
            switch self {
            case .immediate: return nil
            case .oneMinute: return 60
            case .fiveMinutes: return 5 * 60
            }
        }
    }

    @Published var content: String = ""
    @Published var isLoading: Bool = false
    @Published var refreshMode: RefreshMode = .immediate

    private let fileURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var refreshTimer: Timer?

    init(fileURL: URL = Logger.shared.fileURL) {
        self.fileURL = fileURL
        ensureFileExists()
        load()
        applyRefreshMode()
    }

    func start() {
        applyRefreshMode()
    }

    func stop() {
        stopMonitoring()
        stopRefreshTimer()
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

    func share() {
        let picker = NSSharingServicePicker(items: [fileURL])
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
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

    func setRefreshMode(_ mode: RefreshMode) {
        guard refreshMode != mode else { return }
        refreshMode = mode
        applyRefreshMode()
        load()
    }

    private func applyRefreshMode() {
        if refreshMode.interval == nil {
            stopRefreshTimer()
            startMonitoring()
        } else {
            stopMonitoring()
            startRefreshTimer()
        }
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        guard let interval = refreshMode.interval else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.load()
        }
        refreshTimer?.tolerance = min(5, interval * 0.1)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
