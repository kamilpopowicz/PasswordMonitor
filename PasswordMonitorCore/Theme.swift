//
//  Theme.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 11/02/2026.
//

import SwiftUI
import AppKit
import Foundation

public enum PMTheme {
    public enum ThemeMode: String, CaseIterable, Identifiable {
        case auto
        case light
        case dark

        public var id: String { rawValue }
    }

    public static let themeDefaultsKey = "theme_mode"

    public static func preferredColorScheme(from rawValue: String?) -> ColorScheme? {
        let mode = ThemeMode(rawValue: rawValue ?? ThemeMode.auto.rawValue) ?? .auto
        switch mode {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public static var preferredColorSchemeFromDefaults: ColorScheme? {
        preferredColorScheme(from: UserDefaults.standard.string(forKey: themeDefaultsKey))
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        let color = NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
            return best == .darkAqua ? dark : light
        }
        return Color(nsColor: color)
    }

    // Dark: ocean depth. Light: sky blue.
    public static let oceanAbyss = dynamicColor(
        light: NSColor(calibratedRed: 0.91, green: 0.96, blue: 1.00, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.09, alpha: 1.0)
    )
    public static let oceanDeep = dynamicColor(
        light: NSColor(calibratedRed: 0.85, green: 0.93, blue: 1.00, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.13, alpha: 1.0)
    )
    public static let oceanMid = dynamicColor(
        light: NSColor(calibratedRed: 0.77, green: 0.88, blue: 1.00, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.22, alpha: 1.0)
    )
    public static let oceanTeal = dynamicColor(
        light: NSColor(calibratedRed: 0.44, green: 0.74, blue: 0.95, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.38, alpha: 1.0)
    )
    public static let oceanGlow = dynamicColor(
        light: NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.98, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.24, green: 0.76, blue: 0.80, alpha: 1.0)
    )

    public static let textPrimary = dynamicColor(
        light: NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.26, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.98, alpha: 1.0)
    )
    public static let textSecondary = dynamicColor(
        light: NSColor(calibratedRed: 0.28, green: 0.38, blue: 0.50, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.84, alpha: 1.0)
    )
    public static let textMuted = dynamicColor(
        light: NSColor(calibratedRed: 0.40, green: 0.50, blue: 0.62, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.56, green: 0.64, blue: 0.70, alpha: 1.0)
    )

    public static let windowGradient = LinearGradient(
        colors: [oceanAbyss, oceanDeep, oceanMid],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let windowVignette = RadialGradient(
        gradient: Gradient(colors: [
            Color.clear,
            dynamicColor(
                light: NSColor(calibratedRed: 0.62, green: 0.76, blue: 0.90, alpha: 0.35),
                dark: NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.45)
            )
        ]),
        center: .center,
        startRadius: 180,
        endRadius: 760
    )
    public static let windowGlow = RadialGradient(
        gradient: Gradient(colors: [
            dynamicColor(
                light: NSColor(calibratedRed: 0.60, green: 0.80, blue: 1.00, alpha: 0.30),
                dark: NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.38, alpha: 0.25)
            ),
            Color.clear
        ]),
        center: .topLeading,
        startRadius: 40,
        endRadius: 520
    )

    public static let panelGradient = LinearGradient(
        colors: [
            dynamicColor(
                light: NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 0.96),
                dark: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.21, alpha: 0.96)
            ),
            dynamicColor(
                light: NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.00, alpha: 0.94),
                dark: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 0.94)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let panelHighlight = LinearGradient(
        colors: [
            dynamicColor(
                light: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.60),
                dark: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.12)
            ),
            dynamicColor(
                light: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.20),
                dark: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.02)
            ),
            dynamicColor(
                light: NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.46, alpha: 0.10),
                dark: NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.25)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let panelStroke = dynamicColor(
        light: NSColor(calibratedRed: 0.60, green: 0.74, blue: 0.88, alpha: 0.55),
        dark: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.10)
    )
    public static let panelShadow = dynamicColor(
        light: NSColor(calibratedRed: 0.25, green: 0.40, blue: 0.55, alpha: 0.18),
        dark: NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.35)
    )
    public static let fieldBackground = dynamicColor(
        light: NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 0.95),
        dark: NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.19, alpha: 0.95)
    )
    public static let fieldStroke = dynamicColor(
        light: NSColor(calibratedRed: 0.62, green: 0.76, blue: 0.90, alpha: 0.55),
        dark: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.14)
    )

    public static func resolvedTextPrimary(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.98, alpha: 1.0)
            : NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.26, alpha: 1.0)
    }

    public static func resolvedFieldBackground(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.19, alpha: 0.95)
            : NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 0.95)
    }

    public static let accent = oceanGlow
    public static let warning = dynamicColor(
        light: NSColor(calibratedRed: 0.86, green: 0.60, blue: 0.22, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.96, green: 0.74, blue: 0.35, alpha: 1.0)
    )
    public static let danger = dynamicColor(
        light: NSColor(calibratedRed: 0.84, green: 0.24, blue: 0.28, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.95, green: 0.38, blue: 0.40, alpha: 1.0)
    )
    public static let success = dynamicColor(
        light: NSColor(calibratedRed: 0.16, green: 0.62, blue: 0.48, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.38, green: 0.86, blue: 0.62, alpha: 1.0)
    )
}

public struct PMPanelModifier: ViewModifier {
    @Environment(\.pmIsApplyingTheme) private var isApplyingTheme
    public init() {}

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let fillStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(PMTheme.oceanDeep)
            : AnyShapeStyle(PMTheme.panelGradient)
        let highlightStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(PMTheme.panelHighlight)
        content
            .padding()
            .background(
                shape
                    .fill(fillStyle)
                    .overlay(
                        shape.fill(highlightStyle)
                    )
            )
            .overlay(
                shape.stroke(PMTheme.panelStroke, lineWidth: 1)
            )
            .shadow(color: PMTheme.panelShadow.opacity(isApplyingTheme ? 0.15 : 1.0), radius: isApplyingTheme ? 6 : 18, x: 0, y: isApplyingTheme ? 2 : 10)
    }
}

public extension View {
    func pmPanel() -> some View {
        modifier(PMPanelModifier())
    }

    func pmWindowPanel() -> some View {
        PMWindowPanelContainer {
            self
        }
    }

    func pmWindowMinSize() -> some View {
        frame(
            minWidth: PMLayout.windowMinWidth,
            idealWidth: PMLayout.windowMinWidth,
            maxWidth: .infinity,
            minHeight: PMLayout.windowMinHeight,
            idealHeight: PMLayout.windowMinHeight,
            maxHeight: .infinity,
            alignment: .center
        )
        .background(PMWindowMinSizeEnforcer(size: NSSize(width: PMLayout.windowMinWidth, height: PMLayout.windowMinHeight)))
    }

    func pmWindowBackground(reduced: Bool = false) -> some View {
        background(
            ZStack {
                if reduced {
                    PMTheme.oceanDeep
                } else {
                    PMTheme.windowGradient
                    PMTheme.windowGlow
                    PMTheme.windowVignette
                }
            }
            .ignoresSafeArea()
        )
        .tint(PMTheme.accent)
        .foregroundColor(PMTheme.textPrimary)
    }

    func pmThemeTransitionOverlay(isActive: Bool) -> some View {
        overlay(
            Group {
                if isActive {
                    PMThemeTransitionOverlay()
                        .transition(.opacity)
                }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    func pmThemeApplying(_ isApplying: Bool) -> some View {
        environment(\.pmIsApplyingTheme, isApplying)
    }

    @ViewBuilder
    func applyPreferredColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            self.environment(\.colorScheme, scheme)
                .preferredColorScheme(scheme)
        } else {
            self.preferredColorScheme(nil)
        }
    }
}

public struct PMWindowPanelModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        PMWindowPanelContainer {
            content
        }
    }
}

public struct PMWindowPanelContainer<Content: View>: View {
    @Environment(\.pmIsApplyingTheme) private var isApplyingTheme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let fillStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(PMTheme.oceanDeep)
            : AnyShapeStyle(PMTheme.panelGradient)
        let highlightStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(PMTheme.panelHighlight)
        let panel = shape
            .fill(fillStyle)
            .overlay(shape.fill(highlightStyle))
            .overlay(shape.stroke(PMTheme.panelStroke, lineWidth: 1))
            .shadow(
                color: PMTheme.panelShadow.opacity(isApplyingTheme ? 0.15 : 1.0),
                radius: isApplyingTheme ? 6 : 18,
                x: 0,
                y: isApplyingTheme ? 2 : 10
            )

        return ZStack(alignment: .topLeading) {
            panel
                .padding(PMLayout.windowPanelInset)
            content
                .padding(PMLayout.windowPanelInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

public enum PMLayout {
    /// Global minimum window size for consistency across windows.
    public static let windowMinWidth: CGFloat = 782
    public static let windowMinHeight: CGFloat = 452
    /// Global window panel inset for consistent padding and rounded panel placement.
    public static let windowPanelInset: CGFloat = 16
}

private struct PMWindowMinSizeEnforcer: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.minSize = size
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.minSize = size
        }
    }
}

private struct PMIsApplyingThemeKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var pmIsApplyingTheme: Bool {
        get { self[PMIsApplyingThemeKey.self] }
        set { self[PMIsApplyingThemeKey.self] = newValue }
    }
}

private struct PMThemeTransitionOverlay: View {
    var body: some View {
        ZStack {
            PMTheme.windowVignette
                .opacity(0.35)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PMTheme.panelGradient)
                .frame(width: 120, height: 68)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PMTheme.panelStroke, lineWidth: 1)
                )
                .overlay(
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("common_loading")
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                    }
                )
        }
    }
}

public extension Notification.Name {
    static let themeDidChange = Notification.Name("PasswordMonitor.ThemeDidChange")
}
