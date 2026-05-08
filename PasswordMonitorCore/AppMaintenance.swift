//
//  AppMaintenance.swift
//  PasswordMonitorCore
//
//  Created by OpenAI on 08/05/2026.
//

import Foundation

public enum HelperProcessCleanup {
    public struct RunningHelper: Equatable {
        public let processIdentifier: Int32
        public let bundlePath: String?

        public init(processIdentifier: Int32, bundlePath: String?) {
            self.processIdentifier = processIdentifier
            self.bundlePath = bundlePath
        }
    }

    public static func staleHelpers(
        expectedBundlePath: String,
        runningHelpers: [RunningHelper]
    ) -> [RunningHelper] {
        let expectedPath = standardizedPath(expectedBundlePath)
        return runningHelpers.filter { helper in
            guard let bundlePath = helper.bundlePath else {
                return true
            }
            return standardizedPath(bundlePath) != expectedPath
        }
    }

    public static func duplicateHelpers(
        currentProcessIdentifier: Int32,
        runningHelpers: [RunningHelper]
    ) -> [RunningHelper] {
        runningHelpers.filter { $0.processIdentifier != currentProcessIdentifier }
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

public enum AppUninstallCleanupPlan {
    public static let mainBundleIdentifier = "popo.PasswordMonitor"
    public static let helperBundleIdentifier = "popo.PasswordMonitorHelperApp"
    public static let sharedSuiteName = "popo.PasswordMonitor"

    public static var preferenceDomains: [String] {
        [
            mainBundleIdentifier,
            helperBundleIdentifier,
            sharedSuiteName
        ]
    }

    public static func userDataPaths(
        homeDirectory: URL,
        installedAppURL: URL = URL(fileURLWithPath: "/Applications/PasswordMonitor.app"),
        desktopAppURL: URL? = nil
    ) -> [URL] {
        var paths = [
            homeDirectory.appendingPathComponent(".password_monitor.log"),
            homeDirectory.appendingPathComponent("Library/Logs/popo.PasswordMonitor"),
            homeDirectory.appendingPathComponent("Library/Logs/PasswordMonitor"),
            homeDirectory.appendingPathComponent("Library/Caches/popo.PasswordMonitor"),
            homeDirectory.appendingPathComponent("Library/Caches/PasswordMonitor"),
            homeDirectory.appendingPathComponent("Library/Application Support/PasswordMonitor"),
            homeDirectory.appendingPathComponent("Library/Saved Application State/popo.PasswordMonitor.savedState"),
            homeDirectory.appendingPathComponent("Library/Preferences/popo.PasswordMonitor.plist"),
            homeDirectory.appendingPathComponent("Library/Preferences/popo.PasswordMonitorHelperApp.plist"),
            homeDirectory.appendingPathComponent("Library/Containers/popo.PasswordMonitor"),
            homeDirectory.appendingPathComponent("Library/Containers/popo.PasswordMonitorHelperApp"),
            homeDirectory.appendingPathComponent("Library/LaunchAgents/popo.PasswordMonitorHelperApp.plist"),
            installedAppURL
        ]

        if let desktopAppURL {
            paths.append(desktopAppURL)
        }

        return paths
    }
}
