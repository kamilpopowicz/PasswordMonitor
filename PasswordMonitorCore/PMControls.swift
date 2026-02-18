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
                    .stroke(strokeColor(isEnabled: isEnabled), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.45)
            .saturation(isEnabled ? 1.0 : 0.35)
            .brightness(isEnabled ? 0.0 : 0.02)
    }

    private func foregroundColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return PMTheme.textSecondary }
        switch role {
        case .primary, .destructive:
            return Color.white
        case .secondary, .ghost:
            return PMTheme.textPrimary
        }
    }

    private func strokeColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return PMTheme.panelStroke.opacity(0.5) }
        switch role {
        case .primary, .destructive:
            return Color.white.opacity(0.18)
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
                return PMTheme.fieldBackground.opacity(0.75)
            case .secondary:
                return PMTheme.fieldBackground.opacity(0.5)
            case .ghost:
                return Color.clear
            }
        }
        switch role {
        case .primary:
            return PMTheme.accent.opacity(isPressed ? 0.85 : 0.95)
        case .secondary:
            return PMTheme.fieldBackground.opacity(isPressed ? 0.85 : 0.95)
        case .destructive:
            return PMTheme.danger.opacity(isPressed ? 0.85 : 0.95)
        case .ghost:
            return Color.clear
        }
    }

    private func metricsForSize(_ size: PMButtonSize) -> (horizontalPadding: CGFloat, verticalPadding: CGFloat, cornerRadius: CGFloat, font: Font) {
        switch size {
        case .compact:
            return (horizontalPadding: 8, verticalPadding: 4, cornerRadius: 8, font: .system(size: 12, weight: .semibold))
        case .regular:
            return (horizontalPadding: 12, verticalPadding: 7, cornerRadius: 10, font: .system(size: 13, weight: .semibold))
        }
    }
}

public extension View {
    func pmButton(role: PMButtonRole = .secondary, size: PMButtonSize = .regular) -> some View {
        buttonStyle(PMButtonStyle(role: role, size: size))
    }
}
