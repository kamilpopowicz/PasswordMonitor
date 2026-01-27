//
//  Logger.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation

/// Shared logger dla obu targets
public class Logger {
    private let logFileURL: URL
    
    public init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logFileURL = homeDir.appendingPathComponent(".password_monitor.log")
    }
    
    public func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .short,
            timeStyle: .medium
        )
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
        
        // Też print do stdout dla debugging
        print(logMessage, terminator: "")
    }
}
