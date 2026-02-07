//
//  main.swift
//  PasswordMonitorHelper
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import Foundation
import PasswordMonitorCore

// Ten plik będzie uruchamiany przez LaunchAgent
func main() {
    let username = NSUserName()
    let manager = ActiveDirectoryManager()
    let notificationManager = NotificationManager()
    let logger = Logger()

    logger.log("Password Monitor Helper started")

    do {
        let passwordInfo = try manager.getPasswordInfo(for: username)

        logger.log("Password expires in \(passwordInfo.daysUntilExpiration) days")

        if manager.shouldShowWarning(passwordInfo: passwordInfo) {
            // Sprawdź czy powiadomienie już dziś pokazane
            if !notificationManager.isNotificationShownToday {
                logger.log("Showing warning dialog")

                // Pokaż powiadomienie
                notificationManager.showNotification(passwordExpirationDate: passwordInfo.expiryDate)

                // Oznacz jako pokazane dzisiaj
                notificationManager.markNotificationAsShown()
            } else {
                logger.log("Already showed notification today, skipping")
            }
        }

        logger.log("Check completed successfully")
    } catch {
        logger.log("Error: \(error)")
    }
}

main()