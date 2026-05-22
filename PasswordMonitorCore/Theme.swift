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
    public static let overlayScrim = dynamicColor(
        light: NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.12, alpha: 0.20),
        dark: NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.32)
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
    public static let controlTextOnEmphasis = dynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 1.0),
        dark: NSColor(calibratedWhite: 1.0, alpha: 1.0)
    )
    public static let controlStrokeOnEmphasis = dynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.18),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.18)
    )
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

    public static let panelShadowOpacity: Double = 1.0
    public static let panelApplyingShadowOpacity: Double = 0.15
    public static let contentCardHighlightOpacity: Double = 0.72
    public static let contentCardStrokeOpacity: Double = 0.38
    public static let contentCardApplyingStrokeOpacity: Double = 0.7
    public static let contentCardShadowOpacity: Double = 0.22
    public static let contentCardApplyingShadowOpacity: Double = 0.08
    public static let fieldFillOpacity: Double = 1.0
    public static let fieldSubtleFillOpacity: Double = 0.45
    public static let fieldElevatedFillOpacity: Double = 0.75
    public static let fieldStatusFillOpacity: Double = 0.72
    public static let fieldPlaceholderFillOpacity: Double = 0.6
    public static let fieldStrokeOpacity: Double = 1.0
    public static let fieldSoftStrokeOpacity: Double = 0.7
    public static let fieldElevatedStrokeOpacity: Double = 0.8
    public static let themeTransitionVignetteOpacity: Double = 0.35
    public static let alertUrgentStrokeOpacity: Double = 0.6
}

public struct PMPanelModifier: ViewModifier {
    @Environment(\.pmIsApplyingTheme) private var isApplyingTheme
    public init() {}

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PMLayout.panelCornerRadius, style: .continuous)
        let fillStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(PMTheme.oceanDeep)
            : AnyShapeStyle(PMTheme.panelGradient)
        let highlightStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(PMTheme.panelHighlight)
        content
            .padding(PMLayout.panelPadding)
            .background(
                shape
                    .fill(fillStyle)
                    .overlay(
                        shape.fill(highlightStyle)
                    )
            )
            .overlay(
                shape.stroke(PMTheme.panelStroke, lineWidth: PMLayout.hairlineWidth)
            )
            .shadow(
                color: PMTheme.panelShadow.opacity(isApplyingTheme ? PMTheme.panelApplyingShadowOpacity : PMTheme.panelShadowOpacity),
                radius: isApplyingTheme ? PMLayout.panelApplyingShadowRadius : PMLayout.panelShadowRadius,
                x: 0,
                y: isApplyingTheme ? PMLayout.panelApplyingShadowY : PMLayout.panelShadowY
            )
    }
}

public struct PMMenuBarPanelModifier: ViewModifier {
    @Environment(\.pmIsApplyingTheme) private var isApplyingTheme
    public init() {}

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PMLayout.panelCornerRadius, style: .continuous)
        let fillStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(PMTheme.oceanDeep)
            : AnyShapeStyle(PMTheme.panelGradient)
        let highlightStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(PMTheme.panelHighlight)

        content
            .padding(PMLayout.panelPadding)
            .frame(width: PMLayout.menuBarWidth, alignment: .leading)
            .background(
                shape
                    .fill(fillStyle)
                    .overlay(shape.fill(highlightStyle))
            )
            .overlay(
                shape.stroke(PMTheme.panelStroke, lineWidth: PMLayout.hairlineWidth)
            )
            .clipShape(shape)
            .tint(PMTheme.accent)
            .foregroundColor(PMTheme.textPrimary)
    }
}

public struct PMMenuBarWindowConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        if window.styleMask.contains(.titled) {
            window.styleMask.remove(.titled)
        }
    }
}

public struct PMContentCardModifier: ViewModifier {
    @Environment(\.pmIsApplyingTheme) private var isApplyingTheme
    private let padding: CGFloat

    public init(padding: CGFloat = PMLayout.contentCardPadding) {
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PMLayout.contentCardCornerRadius, style: .continuous)
        let fillStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(PMTheme.oceanDeep)
            : AnyShapeStyle(PMTheme.panelGradient)
        let highlightStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(PMTheme.panelHighlight)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(fillStyle)
                    .overlay(shape.fill(highlightStyle).opacity(PMTheme.contentCardHighlightOpacity))
            )
            .overlay(
                shape.stroke(
                    PMTheme.panelStroke.opacity(isApplyingTheme ? PMTheme.contentCardApplyingStrokeOpacity : PMTheme.contentCardStrokeOpacity),
                    lineWidth: PMLayout.hairlineWidth
                )
            )
            .shadow(
                color: PMTheme.panelShadow.opacity(isApplyingTheme ? PMTheme.contentCardApplyingShadowOpacity : PMTheme.contentCardShadowOpacity),
                radius: isApplyingTheme ? PMLayout.contentCardApplyingShadowRadius : PMLayout.contentCardShadowRadius,
                x: 0,
                y: isApplyingTheme ? PMLayout.contentCardApplyingShadowY : PMLayout.contentCardShadowY
            )
    }
}

public struct PMFieldPanelModifier: ViewModifier {
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let fillOpacity: Double
    private let strokeOpacity: Double

    public init(
        padding: CGFloat = 0,
        cornerRadius: CGFloat = PMLayout.fieldCornerRadius,
        fillOpacity: Double = PMTheme.fieldFillOpacity,
        strokeOpacity: Double = PMTheme.fieldStrokeOpacity
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(
                shape
                    .fill(PMTheme.fieldBackground.opacity(fillOpacity))
                    .overlay(
                        shape.stroke(PMTheme.fieldStroke.opacity(strokeOpacity), lineWidth: PMLayout.hairlineWidth)
                    )
            )
    }
}

public extension View {
    func pmPanel() -> some View {
        modifier(PMPanelModifier())
    }

    func pmMenuBarPanel() -> some View {
        modifier(PMMenuBarPanelModifier())
    }

    func pmContentCard(padding: CGFloat = PMLayout.contentCardPadding) -> some View {
        modifier(PMContentCardModifier(padding: padding))
    }

    func pmFieldPanel(
        padding: CGFloat = 0,
        cornerRadius: CGFloat = PMLayout.fieldCornerRadius,
        fillOpacity: Double = PMTheme.fieldFillOpacity,
        strokeOpacity: Double = PMTheme.fieldStrokeOpacity
    ) -> some View {
        modifier(PMFieldPanelModifier(
            padding: padding,
            cornerRadius: cornerRadius,
            fillOpacity: fillOpacity,
            strokeOpacity: strokeOpacity
        ))
    }

    func pmWindowPanel() -> some View {
        PMWindowPanelContainer {
            self
        }
    }

    func pmWindowMinSize() -> some View {
        frame(
            minWidth: PMLayout.defaultWindowWidth,
            idealWidth: PMLayout.defaultWindowWidth,
            maxWidth: .infinity,
            minHeight: PMLayout.defaultWindowHeight,
            idealHeight: PMLayout.defaultWindowHeight,
            maxHeight: .infinity,
            alignment: .center
        )
        .background(PMWindowMinSizeEnforcer(size: NSSize(width: PMLayout.defaultWindowWidth, height: PMLayout.defaultWindowHeight)))
    }

    func pmWindowFixedSize() -> some View {
        frame(
            width: PMLayout.defaultWindowWidth,
            height: PMLayout.defaultWindowHeight,
            alignment: .center
        )
        .background(PMWindowSizeEnforcer(size: NSSize(width: PMLayout.defaultWindowWidth, height: PMLayout.defaultWindowHeight)))
    }

    func pmWindowMinSize(width: CGFloat, height: CGFloat) -> some View {
        frame(
            minWidth: width,
            idealWidth: width,
            maxWidth: .infinity,
            minHeight: height,
            idealHeight: height,
            maxHeight: .infinity,
            alignment: .center
        )
        .background(PMWindowMinSizeEnforcer(size: NSSize(width: width, height: height)))
    }

    func pmMultilineText(alignment: TextAlignment = .leading) -> some View {
        modifier(PMMultilineTextModifier(alignment: alignment))
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
        .animation(.easeInOut(duration: PMMotion.themeTransitionDuration), value: isActive)
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
        let shape = RoundedRectangle(cornerRadius: PMLayout.panelCornerRadius, style: .continuous)
        let fillStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(PMTheme.oceanDeep)
            : AnyShapeStyle(PMTheme.panelGradient)
        let highlightStyle: AnyShapeStyle = isApplyingTheme
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(PMTheme.panelHighlight)
        let panel = shape
            .fill(fillStyle)
            .overlay(shape.fill(highlightStyle))
            .overlay(shape.stroke(PMTheme.panelStroke, lineWidth: PMLayout.hairlineWidth))
            .shadow(
                color: PMTheme.panelShadow.opacity(isApplyingTheme ? PMTheme.panelApplyingShadowOpacity : PMTheme.panelShadowOpacity),
                radius: isApplyingTheme ? PMLayout.panelApplyingShadowRadius : PMLayout.panelShadowRadius,
                x: 0,
                y: isApplyingTheme ? PMLayout.panelApplyingShadowY : PMLayout.panelShadowY
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

public struct PMWindowContentContainer<Content: View>: View {
    private let alignment: Alignment
    private let content: Content

    public init(alignment: Alignment = .topLeading, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: some View {
        content
            .frame(
                minWidth: PMLayout.windowContentMinWidth,
                maxWidth: .infinity,
                alignment: alignment
            )
            .padding(.horizontal, PMLayout.windowContentHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

public struct PMWindowActionBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(
                minWidth: PMLayout.windowContentMinWidth,
                maxWidth: .infinity,
                alignment: .center
            )
            .padding(.horizontal, PMLayout.windowContentHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, PMLayout.sectionSpacing)
    }
}

public struct PMAdaptiveActionRow<Content: View>: View {
    private let horizontalAlignment: VerticalAlignment
    private let verticalAlignment: HorizontalAlignment
    private let spacing: CGFloat
    private let content: () -> Content

    public init(
        horizontalAlignment: VerticalAlignment = .center,
        verticalAlignment: HorizontalAlignment = .leading,
        spacing: CGFloat = PMLayout.compactSpacing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: horizontalAlignment, spacing: spacing) {
                content()
            }

            VStack(alignment: verticalAlignment, spacing: spacing) {
                content()
            }
        }
    }
}

public struct PMMultilineTextModifier: ViewModifier {
    private let alignment: TextAlignment

    public init(alignment: TextAlignment = .leading) {
        self.alignment = alignment
    }

    public func body(content: Content) -> some View {
        content
            .multilineTextAlignment(alignment)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

public struct PMWindowFooterHost: View {
    public init() {}

    public var body: some View {
        PMWindowFooter()
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

public enum PMLayout {
    /// Global fixed window size for consistency across windows.
    public static let defaultWindowWidth: CGFloat = 660
    public static let defaultWindowHeight: CGFloat = 620
    public static let defaultWindowMinWidth = defaultWindowWidth
    public static let defaultWindowMinHeight = defaultWindowHeight
    public static let windowMinWidth = defaultWindowMinWidth
    public static let windowMinHeight = defaultWindowMinHeight
    public static let passwordChangeWindowWidth = defaultWindowWidth
    public static let passwordChangeWindowHeight = defaultWindowHeight
    public static let passwordChangeWindowMinWidth = defaultWindowMinWidth
    public static let passwordChangeWindowMinHeight = defaultWindowMinHeight
    public static let passwordChangeFieldMinWidth: CGFloat = 260
    public static let passwordStrengthMeterHeight: CGFloat = 8
    public static let passwordStrengthSegmentMinWidth: CGFloat = 34
    public static let windowFocusRetryCount = 12
    public static let windowContentWidth: CGFloat = defaultWindowWidth - (contentPadding * 2)
    public static let windowContentMinWidth: CGFloat = windowContentWidth
    public static let windowContentHorizontalPadding: CGFloat = contentPadding
    public static let noSpacing: CGFloat = 0
    public static let zeroMinLength: CGFloat = 0
    /// Global window panel inset for consistent padding and rounded panel placement.
    public static let windowPanelInset: CGFloat = 16
    public static let hairlineWidth: CGFloat = 1

    public static let panelPadding: CGFloat = 16
    public static let panelCornerRadius: CGFloat = 18
    public static let panelShadowRadius: CGFloat = 18
    public static let panelApplyingShadowRadius: CGFloat = 6
    public static let panelShadowY: CGFloat = 10
    public static let panelApplyingShadowY: CGFloat = 2

    public static let contentPadding: CGFloat = 24
    public static let contentCardPadding: CGFloat = 16
    public static let contentCardHeroPadding: CGFloat = 18
    public static let contentCardCompactPadding: CGFloat = 8
    public static let contentCardCornerRadius: CGFloat = 16
    public static let contentCardShadowRadius: CGFloat = 8
    public static let contentCardApplyingShadowRadius: CGFloat = 4
    public static let contentCardShadowY: CGFloat = 3
    public static let contentCardApplyingShadowY: CGFloat = 1

    public static let fieldCornerRadius: CGFloat = 12
    public static let smallFieldCornerRadius: CGFloat = 8
    public static let updateCandidateCornerRadius: CGFloat = 14

    public static let cardSpacing: CGFloat = 16
    public static let sectionSpacing: CGFloat = 12
    public static let controlSpacing: CGFloat = 10
    public static let compactSpacing: CGFloat = 8
    public static let tightSpacing: CGFloat = 6
    public static let microSpacing: CGFloat = 2
    public static let metadataDotSize: CGFloat = 3
    public static let defaultPadding: CGFloat = 16
    public static let footerHorizontalPadding: CGFloat = 16
    public static let footerVerticalPadding: CGFloat = 12
    public static let footerMinHeight: CGFloat = 46

    public static let settingsNumberFieldWidth: CGFloat = 60
    public static let settingsLanguageFormPadding: CGFloat = 16
    public static let languageAssistMinHeight: CGFloat = 80
    public static let languageAssistEditorPadding: CGFloat = 6
    public static let languageAssistPlaceholderPadding: CGFloat = 8
    public static let aiOverlayBlurRadius: CGFloat = 6
    public static let progressOverlayScale: CGFloat = 1.2
    public static let inlineProgressScale: CGFloat = 0.8
    public static let statusIndicatorSize: CGFloat = 10
    public static let requirementStatusDotSize: CGFloat = 8
    public static let requirementStatusTrailingPadding: CGFloat = 6
    public static let aiRequirementsOptionColumnWidth: CGFloat = 160
    public static let aiRequirementsStatusColumnWidth: CGFloat = 14
    public static let aiRequirementsOptionLeadingInset: CGFloat = 12
    public static let aiRequirementsValueColumnWidth: CGFloat = 160
    public static let aiRequirementsButtonColumnWidth: CGFloat = 160
    public static let aiRequirementsContentPadding: CGFloat = 16
    public static let aiRequirementsFooterHorizontalPadding: CGFloat = 16
    public static let aiRequirementsFooterHeight: CGFloat = 46

    public static let logsSearchButtonSpacing: CGFloat = 6
    public static let logsSearchButtonWidth: CGFloat = 32
    public static let logsCompactSearchFieldWidth: CGFloat = 140
    public static let logsCompactSearchColumnWidth: CGFloat = 178
    public static let logsFilterLabelWidth: CGFloat = 70
    public static let logsRefreshPickerWidth: CGFloat = 220
    public static let logTextInsetWidth: CGFloat = 12
    public static let logTextInsetHeight: CGFloat = 10
    public static let logFollowThreshold: CGFloat = 40

    public static let menuBarWidth: CGFloat = 260
    public static let menuStatusPadding: CGFloat = 12
    public static let menuStatusNumberSize: CGFloat = 22
    public static let menuStatusIndicatorSize: CGFloat = 8
    public static let menuButtonMinimumScale: CGFloat = 0.85
    public static let menuBarIconSize: CGFloat = 18
    public static let centeringMultiplier: CGFloat = 0.5

    public static let aboutHeroTitleSize: CGFloat = 31
    public static let aboutIconImageSize: CGFloat = 96
    public static let aboutIconImageFallbackSize: CGFloat = 72

    public static let themeTransitionPreviewWidth: CGFloat = 120
    public static let themeTransitionPreviewHeight: CGFloat = 68

    public static let alertWindowMinWidth: CGFloat = 420
    public static let alertWindowMinHeight: CGFloat = 240
    public static let alertWidth: CGFloat = 420
    public static let alertAdviceMaxWidth: CGFloat = 320
    public static let alertIconSize: CGFloat = 48
    public static let alertTimerUrgentFontSize: CGFloat = 32
    public static let alertTimerFontSize: CGFloat = 26
    public static let alertTimerCornerRadius: CGFloat = 10
    public static let alertTimerVerticalPadding: CGFloat = 10
    public static let alertTimerHorizontalPadding: CGFloat = 20
    public static let alertButtonMinWidth: CGFloat = 100
    public static let alertEndTestButtonMinWidth: CGFloat = 120
    public static let alertContentPadding: CGFloat = 24
    public static let alertOuterPadding: CGFloat = 16
}

public enum PMControlMetrics {
    public static let hiddenOpacity: Double = 0
    public static let visibleOpacity: Double = 1
    public static let compactHorizontalPadding: CGFloat = 8
    public static let compactVerticalPadding: CGFloat = 4
    public static let compactCornerRadius: CGFloat = 8
    public static let compactFontSize: CGFloat = 12
    public static let regularHorizontalPadding: CGFloat = 12
    public static let regularVerticalPadding: CGFloat = 7
    public static let regularCornerRadius: CGFloat = 10
    public static let regularFontSize: CGFloat = 13
    public static let strokeWidth: CGFloat = 1
    public static let pressedOpacity: Double = 0.9
    public static let enabledOpacity: Double = 1.0
    public static let disabledOpacity: Double = 0.45
    public static let enabledSaturation: Double = 1.0
    public static let disabledSaturation: Double = 0.35
    public static let enabledBrightness: Double = 0.0
    public static let disabledBrightness: Double = 0.02
    public static let disabledStrokeOpacity: Double = 0.5
    public static let disabledPrimaryFillOpacity: Double = 0.75
    public static let disabledSecondaryFillOpacity: Double = 0.5
    public static let pressedFillOpacity: Double = 0.85
    public static let restingFillOpacity: Double = 0.95
}

public enum PMMotion {
    public static let quickAnimationDuration: Double = 0.18
    public static let themeTransitionDuration: Double = 0.2
    public static let relaunchDelay: Double = 0.25
    public static let languagePromptDelay: Double = 0.3
    public static let windowFocusRetryDelay: Double = 0.05
    public static let mainAppActivationDelay: Double = 0.15
}

public struct PMWindowFooter: View {
    public init() {}

    public var body: some View {
        VStack(spacing: PMLayout.microSpacing) {
            Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
        }
        .font(.caption2)
        .foregroundColor(PMTheme.textSecondary)
        .padding(.horizontal, PMLayout.footerHorizontalPadding)
        .padding(.vertical, PMLayout.footerVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: PMLayout.footerMinHeight, alignment: .center)
    }
}

private struct PMWindowSizeEnforcer: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.minSize = size
            view.window?.maxSize = size
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.minSize = size
            nsView.window?.maxSize = size
        }
    }
}

private struct PMWindowMinSizeEnforcer: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.minSize = size
            view.window?.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.minSize = size
            nsView.window?.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
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
                .opacity(PMTheme.themeTransitionVignetteOpacity)
            RoundedRectangle(cornerRadius: PMLayout.fieldCornerRadius, style: .continuous)
                .fill(PMTheme.panelGradient)
                .frame(width: PMLayout.themeTransitionPreviewWidth, height: PMLayout.themeTransitionPreviewHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: PMLayout.fieldCornerRadius, style: .continuous)
                        .stroke(PMTheme.panelStroke, lineWidth: PMLayout.hairlineWidth)
                )
                .overlay(
                    VStack(spacing: PMLayout.compactSpacing) {
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
