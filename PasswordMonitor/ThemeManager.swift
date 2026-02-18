//
//  ThemeManager.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 18/02/2026.
//

import SwiftUI
import AppKit
import Combine
import PasswordMonitorCore

@MainActor
final class ThemeManager: ObservableObject {
    @Published var mode: PMTheme.ThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: PMTheme.themeDefaultsKey)
            isApplyingTheme = true
            Task { @MainActor in
                // Najpierw pokaż overlay, potem przełącz wygląd.
                await Task.yield()
                applyAppearance()
                NotificationCenter.default.post(name: .themeDidChange, object: nil)
                try? await Task.sleep(nanoseconds: 300_000_000)
                isApplyingTheme = false
            }
        }
    }

    @Published var isApplyingTheme = false

    init() {
        let raw = UserDefaults.standard.string(forKey: PMTheme.themeDefaultsKey)
        mode = PMTheme.ThemeMode(rawValue: raw ?? PMTheme.ThemeMode.auto.rawValue) ?? .auto
        applyAppearance()
    }

    var preferredScheme: ColorScheme? {
        PMTheme.preferredColorScheme(from: mode.rawValue)
    }

    var isDarkAppearance: Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .auto:
            let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
            return best == .darkAqua
        @unknown default:
            return false
        }
    }

    private func applyAppearance() {
        switch mode {
        case .auto:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        @unknown default:
            NSApp.appearance = nil
        }
    }
}
