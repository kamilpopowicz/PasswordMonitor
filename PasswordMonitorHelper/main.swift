//
//  main.swift
//  PasswordMonitorHelper
//
//  Created by Kamil Popowicz on 26/01/2026.
//

import Foundation
import PasswordMonitorCore
import PasswordMonitorCore
print("PasswordMonitorCore imported successfully")
let manager = ActiveDirectoryManager()
print("ActiveDirectoryManager initialized")

// Ten plik będzie uruchamiany przez LaunchAgent
func main() {
    let username = NSUserName()
    let manager = ActiveDirectoryManager()
    let notificationManager = NotificationManager()
    let logger = Logger()  // Użyj shared logger
    
    logger.log("Password Monitor Helper started")
    
    do {
        let passwordInfo = try manager.getPasswordInfo(for: username)
        
        logger.log("Password expires in \(passwordInfo.daysUntilExpiration) days")
        
        if manager.shouldShowWarning(passwordInfo: passwordInfo) {
            if notificationManager.shouldShowTodayNotification() {
                logger.log("Showing warning dialog")
                
                if notificationManager.showPasswordWarning(
                    daysLeft: passwordInfo.daysUntilExpiration,
                    expiryDate: passwordInfo.expiryDate
                ) {
                    notificationManager.openPasswordSettings()
                }
                
                notificationManager.markNotificationShown()
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
