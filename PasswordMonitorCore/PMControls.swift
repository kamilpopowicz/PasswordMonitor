//
//  PMControls.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 18/02/2026.
//

import SwiftUI

public enum PMButtonRole {
    case primary
    case secondary
    case destructive
    case ghost
}

public enum PMButtonSize {
    case compact
    case regular
}

public struct PMButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let role: PMButtonRole
    private let size: PMButtonSize

    public init(role: PMButtonRole, size: PMButtonSize) {
        self.role = role
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        let metrics = metricsForSize(size)
        return configuration.label
            .font(metrics.font)
            .foregroundColor(foregroundColor(isEnabled: isEnabled))
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .background(backgroundColor(isPressed: configuration.isPressed, isEnabled: isEnabled))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .stroke(strokeColor(isEnabled: isEnabled), lineWidth: PMControlMetrics.strokeWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? PMControlMetrics.pressedOpacity : PMControlMetrics.enabledOpacity) : PMControlMetrics.disabledOpacity)
            .saturation(isEnabled ? PMControlMetrics.enabledSaturation : PMControlMetrics.disabledSaturation)
            .brightness(isEnabled ? PMControlMetrics.enabledBrightness : PMControlMetrics.disabledBrightness)
    }

    private func foregroundColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return PMTheme.textSecondary }
        switch role {
        case .primary, .destructive:
            return PMTheme.controlTextOnEmphasis
        case .secondary, .ghost:
            return PMTheme.textPrimary
        }
    }

    private func strokeColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return PMTheme.panelStroke.opacity(PMControlMetrics.disabledStrokeOpacity) }
        switch role {
        case .primary, .destructive:
            return PMTheme.controlStrokeOnEmphasis
        case .secondary:
            return PMTheme.fieldStroke
        case .ghost:
            return PMTheme.panelStroke
        }
    }

    private func backgroundColor(isPressed: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            switch role {
            case .primary, .destructive:
                return PMTheme.fieldBackground.opacity(PMControlMetrics.disabledPrimaryFillOpacity)
            case .secondary:
                return PMTheme.fieldBackground.opacity(PMControlMetrics.disabledSecondaryFillOpacity)
            case .ghost:
                return Color.clear
            }
        }
        switch role {
        case .primary:
            return PMTheme.accent.opacity(isPressed ? PMControlMetrics.pressedFillOpacity : PMControlMetrics.restingFillOpacity)
        case .secondary:
            return PMTheme.fieldBackground.opacity(isPressed ? PMControlMetrics.pressedFillOpacity : PMControlMetrics.restingFillOpacity)
        case .destructive:
            return PMTheme.danger.opacity(isPressed ? PMControlMetrics.pressedFillOpacity : PMControlMetrics.restingFillOpacity)
        case .ghost:
            return Color.clear
        }
    }

    private func metricsForSize(_ size: PMButtonSize) -> (horizontalPadding: CGFloat, verticalPadding: CGFloat, cornerRadius: CGFloat, font: Font) {
        switch size {
        case .compact:
            return (
                horizontalPadding: PMControlMetrics.compactHorizontalPadding,
                verticalPadding: PMControlMetrics.compactVerticalPadding,
                cornerRadius: PMControlMetrics.compactCornerRadius,
                font: .system(size: PMControlMetrics.compactFontSize, weight: .semibold)
            )
        case .regular:
            return (
                horizontalPadding: PMControlMetrics.regularHorizontalPadding,
                verticalPadding: PMControlMetrics.regularVerticalPadding,
                cornerRadius: PMControlMetrics.regularCornerRadius,
                font: .system(size: PMControlMetrics.regularFontSize, weight: .semibold)
            )
        }
    }
}

public extension View {
    func pmButton(role: PMButtonRole = .secondary, size: PMButtonSize = .regular) -> some View {
        buttonStyle(PMButtonStyle(role: role, size: size))
    }
}
