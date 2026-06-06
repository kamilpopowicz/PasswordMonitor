//
//  DashboardStatusCopy.swift
//  PasswordMonitor
//
//  Created by Codex on 31/05/2026.
//

import Foundation
import PasswordMonitorCore

enum DashboardStatusCopy {
    static func message(for statusKey: ServiceModuleStatusKey?) -> String? {
        guard let statusKey else { return nil }
        let key = PMDashboardSpec.statusLocalizationKey(for: statusKey)

        return NSLocalizedString(
            key,
            tableName: nil,
            bundle: .main,
            value: fallbackValue(for: statusKey),
            comment: "Dashboard module status message"
        )
    }

    private static func fallbackValue(for statusKey: ServiceModuleStatusKey) -> String {
        if Locale.preferredLanguages.first?.hasPrefix("pl") == true {
            switch statusKey {
            case .awaitingPortalConfiguration:
                return "Oczekiwanie na konfigurację portalu HR."
            case .awaitingNetworkDrivesConfiguration:
                return "Oczekiwanie na konfigurację dysków sieciowych."
            }
        }

        switch statusKey {
        case .awaitingPortalConfiguration:
            return "Waiting for HR portal configuration."
        case .awaitingNetworkDrivesConfiguration:
            return "Waiting for network drives configuration."
        }
    }
}

extension ServiceModuleSnapshot {
    var localizedStatusMessage: String? {
        DashboardStatusCopy.message(for: statusKey)
    }
}
