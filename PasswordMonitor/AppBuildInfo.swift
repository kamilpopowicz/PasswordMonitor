//
//  AppBuildInfo.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 19/02/2026.
//

import Foundation

enum AppBuildInfo {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var buildDate: String {
        guard let url = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date
        else {
            return "unknown"
        }
        return dateFormatter.string(from: date)
    }

    static var footerLine: String {
        "v\(version) (\(build)) · \(buildDate)"
    }
}
