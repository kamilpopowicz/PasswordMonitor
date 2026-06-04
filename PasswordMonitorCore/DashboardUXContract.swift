//
//  DashboardUXContract.swift
//  PasswordMonitorCore
//
//  Created by Kamil Popowicz on 30/05/2026.
//

import Foundation

public enum AppDestinationID: String, CaseIterable, Codable, Sendable {
    case home
    case password
    case settings
    case help
}

public enum ServiceModuleID: String, CaseIterable, Codable, Sendable {
    case password
    case hrPortal
    case networkDrives
}

public enum DashboardTileID: String, CaseIterable, Codable, Sendable {
    case password
    case hrPortal
    case networkDrives
    case help
}

public enum BubbleSeverity: String, CaseIterable, Codable, Sendable {
    case healthy
    case warning
    case urgent
    case critical
}

public enum DomainConnectivityState: String, CaseIterable, Codable, Sendable {
    case online
    case degraded
    case offline
}

public enum ADResolutionState: String, CaseIterable, Codable, Sendable {
    case resolved
    case fallback
    case unavailable
}

public struct BubbleAnchor: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct BubbleLayoutSpec: Codable, Hashable, Sendable {
    public let anchor: BubbleAnchor
    public let baseRadius: Double
    public let minRadius: Double
    public let maxRadius: Double
    public let collisionWeight: Double

    public init(
        anchor: BubbleAnchor,
        baseRadius: Double,
        minRadius: Double,
        maxRadius: Double,
        collisionWeight: Double
    ) {
        self.anchor = anchor
        self.baseRadius = baseRadius
        self.minRadius = minRadius
        self.maxRadius = maxRadius
        self.collisionWeight = collisionWeight
    }
}

public struct SpringSpec: Codable, Hashable, Sendable {
    public let response: Double
    public let dampingFraction: Double
    public let blendDuration: Double

    public init(response: Double, dampingFraction: Double, blendDuration: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
    }
}

public struct MotionSpec: Codable, Hashable, Sendable {
    public let maxOffsetX: Double
    public let maxOffsetY: Double
    public let cursorInfluence: Double
    public let returnSpring: SpringSpec
    public let disabledByReduceMotion: Bool

    public init(
        maxOffsetX: Double,
        maxOffsetY: Double,
        cursorInfluence: Double,
        returnSpring: SpringSpec,
        disabledByReduceMotion: Bool
    ) {
        self.maxOffsetX = maxOffsetX
        self.maxOffsetY = maxOffsetY
        self.cursorInfluence = cursorInfluence
        self.returnSpring = returnSpring
        self.disabledByReduceMotion = disabledByReduceMotion
    }
}

public struct DashboardState: Codable, Hashable, Sendable {
    public let daysUntilExpiration: Int
    public let connectivity: DomainConnectivityState
    public let adStatus: ADResolutionState

    public init(
        daysUntilExpiration: Int,
        connectivity: DomainConnectivityState,
        adStatus: ADResolutionState
    ) {
        self.daysUntilExpiration = daysUntilExpiration
        self.connectivity = connectivity
        self.adStatus = adStatus
    }
}

public enum ServiceModuleRuntimeState: String, CaseIterable, Codable, Sendable {
    case loading
    case healthy
    case warning
    case error
    case unavailable
}

public enum ServiceModuleAuthState: String, CaseIterable, Codable, Sendable {
    case notRequired
    case authenticated
    case authenticationRequired
    case sessionExpired
}

public enum ServiceModuleConnectivityState: String, CaseIterable, Codable, Sendable {
    case online
    case degraded
    case offline
}

public enum ServiceModuleActionID: String, CaseIterable, Codable, Sendable {
    case open
    case refresh
    case retry
    case openExternal
}

public enum ServiceModuleLaunchMode: String, CaseIterable, Codable, Sendable {
    case nativePanel
    case inAppWebView
}

public enum ServiceModuleStatusKey: String, CaseIterable, Codable, Sendable {
    case awaitingPortalConfiguration
    case awaitingNetworkDrivesConfiguration
}

public struct ServiceModulePresentationSpec: Codable, Hashable, Sendable {
    public let launchMode: ServiceModuleLaunchMode
    public let requiresNetwork: Bool
    public let requiresAuthenticatedSession: Bool
    public let allowedActions: [ServiceModuleActionID]

    public init(
        launchMode: ServiceModuleLaunchMode,
        requiresNetwork: Bool,
        requiresAuthenticatedSession: Bool,
        allowedActions: [ServiceModuleActionID]
    ) {
        self.launchMode = launchMode
        self.requiresNetwork = requiresNetwork
        self.requiresAuthenticatedSession = requiresAuthenticatedSession
        self.allowedActions = allowedActions
    }
}

public struct ServiceModuleSnapshot: Codable, Hashable, Sendable {
    public let moduleID: ServiceModuleID
    public let runtimeState: ServiceModuleRuntimeState
    public let connectivity: ServiceModuleConnectivityState
    public let authState: ServiceModuleAuthState
    public let statusKey: ServiceModuleStatusKey?
    public let lastRefreshAt: Date?
    public let primaryAction: ServiceModuleActionID
    public let secondaryActions: [ServiceModuleActionID]

    public init(
        moduleID: ServiceModuleID,
        runtimeState: ServiceModuleRuntimeState,
        connectivity: ServiceModuleConnectivityState,
        authState: ServiceModuleAuthState,
        statusKey: ServiceModuleStatusKey?,
        lastRefreshAt: Date?,
        primaryAction: ServiceModuleActionID,
        secondaryActions: [ServiceModuleActionID]
    ) {
        self.moduleID = moduleID
        self.runtimeState = runtimeState
        self.connectivity = connectivity
        self.authState = authState
        self.statusKey = statusKey
        self.lastRefreshAt = lastRefreshAt
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }
}

public enum PMDashboardSpec {
    /// Canonical state thresholds from UX boards:
    /// 30+ days healthy, 14-29 warning, 2-13 urgent, <=24h critical.
    public static func severity(for daysUntilExpiration: Int) -> BubbleSeverity {
        switch daysUntilExpiration {
        case ...1:
            return .critical
        case ...13:
            return .urgent
        case ...29:
            return .warning
        default:
            return .healthy
        }
    }

    /// Radius scale is deterministic and does not depend on animation runtime.
    public static func radiusScale(for severity: BubbleSeverity) -> Double {
        switch severity {
        case .healthy:
            return 0.72
        case .warning:
            return 1.00
        case .urgent:
            return 1.22
        case .critical:
            return 1.54
        }
    }

    /// Non-password service tiles use this deterministic state mapping.
    public static func tileSeverity(for runtimeState: ServiceModuleRuntimeState) -> BubbleSeverity {
        switch runtimeState {
        case .healthy:
            return .healthy
        case .warning:
            return .warning
        case .loading:
            return .healthy
        case .error:
            return .urgent
        case .unavailable:
            return .critical
        }
    }

    /// Safe vertical gap between maximum critical bubble radius and CTA top edge.
    public static let ctaSafeGap: Double = 14

    /// Shared motion behavior for all dashboard tiles.
    public static let defaultMotionSpec = MotionSpec(
        maxOffsetX: 12,
        maxOffsetY: 10,
        cursorInfluence: 0.22,
        returnSpring: SpringSpec(response: 0.36, dampingFraction: 0.82, blendDuration: 0.05),
        disabledByReduceMotion: true
    )

    /// Anchors are normalized to the dashboard board coordinate space [0, 1].
    public static let dashboardLayout: [DashboardTileID: BubbleLayoutSpec] = [
        .password: BubbleLayoutSpec(
            anchor: BubbleAnchor(x: 0.39, y: 0.50),
            baseRadius: 118,
            minRadius: 88,
            maxRadius: 190,
            collisionWeight: 1.0
        ),
        .help: BubbleLayoutSpec(
            anchor: BubbleAnchor(x: 0.79, y: 0.46),
            baseRadius: 64,
            minRadius: 56,
            maxRadius: 68,
            collisionWeight: 0.64
        ),
        .networkDrives: BubbleLayoutSpec(
            anchor: BubbleAnchor(x: 0.66, y: 0.70),
            baseRadius: 88,
            minRadius: 72,
            maxRadius: 102,
            collisionWeight: 0.78
        ),
        .hrPortal: BubbleLayoutSpec(
            anchor: BubbleAnchor(x: 0.62, y: 0.36),
            baseRadius: 76,
            minRadius: 62,
            maxRadius: 90,
            collisionWeight: 0.70
        )
    ]

    /// Shared destination color map keeps sidebar navigation visually consistent.
    public static let destinationColorHex: [AppDestinationID: String] = [
        .home: "#72D8E1",
        .password: "#86E58C",
        .settings: "#5F8CFF",
        .help: "#F7C95D"
    ]

    /// Shared tile color map keeps dashboard bubbles visually consistent with the service language.
    public static let dashboardTileColorHex: [DashboardTileID: String] = [
        .password: "#86E58C",
        .hrPortal: "#A682FF",
        .networkDrives: "#5F8CFF",
        .help: "#F7C95D"
    ]

    public static let tileServiceModule: [DashboardTileID: ServiceModuleID?] = [
        .password: .password,
        .hrPortal: .hrPortal,
        .networkDrives: .networkDrives,
        .help: nil
    ]

    /// In v2.0 all service modules are launched from Home dashboard context.
    public static let moduleDestination: [ServiceModuleID: AppDestinationID] = [
        .password: .password,
        .hrPortal: .home,
        .networkDrives: .home
    ]

    public static let serviceModulePresentation: [ServiceModuleID: ServiceModulePresentationSpec] = [
        .password: ServiceModulePresentationSpec(
            launchMode: .nativePanel,
            requiresNetwork: true,
            requiresAuthenticatedSession: true,
            allowedActions: [.open, .refresh, .retry]
        ),
        .hrPortal: ServiceModulePresentationSpec(
            launchMode: .inAppWebView,
            requiresNetwork: true,
            requiresAuthenticatedSession: true,
            allowedActions: [.open, .refresh, .retry, .openExternal]
        ),
        .networkDrives: ServiceModulePresentationSpec(
            launchMode: .nativePanel,
            requiresNetwork: true,
            requiresAuthenticatedSession: true,
            allowedActions: [.open, .refresh, .retry]
        )
    ]

    /// Placeholder snapshots define consistent UI before module backends are implemented.
    public static let initialServiceModuleSnapshot: [ServiceModuleID: ServiceModuleSnapshot] = [
        .password: ServiceModuleSnapshot(
            moduleID: .password,
            runtimeState: .healthy,
            connectivity: .online,
            authState: .authenticated,
            statusKey: nil,
            lastRefreshAt: nil,
            primaryAction: .open,
            secondaryActions: [.refresh]
        ),
        .hrPortal: ServiceModuleSnapshot(
            moduleID: .hrPortal,
            runtimeState: .loading,
            connectivity: .degraded,
            authState: .authenticationRequired,
            statusKey: .awaitingPortalConfiguration,
            lastRefreshAt: nil,
            primaryAction: .open,
            secondaryActions: [.refresh, .openExternal]
        ),
        .networkDrives: ServiceModuleSnapshot(
            moduleID: .networkDrives,
            runtimeState: .loading,
            connectivity: .degraded,
            authState: .authenticationRequired,
            statusKey: .awaitingNetworkDrivesConfiguration,
            lastRefreshAt: nil,
            primaryAction: .open,
            secondaryActions: [.refresh]
        )
    ]

    /// Stable localization keys consumed by UI layer adapters.
    public static func statusLocalizationKey(for statusKey: ServiceModuleStatusKey) -> String {
        switch statusKey {
        case .awaitingPortalConfiguration:
            return "dashboard_status_awaiting_portal_configuration"
        case .awaitingNetworkDrivesConfiguration:
            return "dashboard_status_awaiting_network_drives_configuration"
        }
    }

    /// Contract integrity checks for future service modules formalization.
    public static func serviceModuleContractValidationErrors() -> [String] {
        var errors: [String] = []

        for module in ServiceModuleID.allCases {
            guard let presentation = serviceModulePresentation[module] else {
                errors.append("Missing serviceModulePresentation for \(module.rawValue)")
                continue
            }
            guard let snapshot = initialServiceModuleSnapshot[module] else {
                errors.append("Missing initialServiceModuleSnapshot for \(module.rawValue)")
                continue
            }
            if moduleDestination[module] == nil {
                errors.append("Missing moduleDestination for \(module.rawValue)")
            }
            if snapshot.moduleID != module {
                errors.append("Snapshot moduleID mismatch for \(module.rawValue)")
            }
            if !presentation.allowedActions.contains(snapshot.primaryAction) {
                errors.append("Primary action \(snapshot.primaryAction.rawValue) is not allowed for \(module.rawValue)")
            }

            let uniqueSecondary = Set(snapshot.secondaryActions)
            if uniqueSecondary.count != snapshot.secondaryActions.count {
                errors.append("Duplicate secondary actions for \(module.rawValue)")
            }
            let illegalSecondary = uniqueSecondary.filter { !presentation.allowedActions.contains($0) }
            if !illegalSecondary.isEmpty {
                let illegalValues = illegalSecondary.map(\.rawValue).sorted().joined(separator: ", ")
                errors.append("Illegal secondary actions for \(module.rawValue): \(illegalValues)")
            }
            if uniqueSecondary.contains(snapshot.primaryAction) {
                errors.append("Primary action duplicated in secondary actions for \(module.rawValue)")
            }
        }

        for key in moduleDestination.keys where !ServiceModuleID.allCases.contains(key) {
            errors.append("moduleDestination contains unknown module key \(key.rawValue)")
        }
        for key in serviceModulePresentation.keys where !ServiceModuleID.allCases.contains(key) {
            errors.append("serviceModulePresentation contains unknown module key \(key.rawValue)")
        }
        for key in initialServiceModuleSnapshot.keys where !ServiceModuleID.allCases.contains(key) {
            errors.append("initialServiceModuleSnapshot contains unknown module key \(key.rawValue)")
        }

        return errors
    }
}
