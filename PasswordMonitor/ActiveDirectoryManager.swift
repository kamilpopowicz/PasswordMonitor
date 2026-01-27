//
//  PasswordInfo.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 26/01/2026.
//


import Foundation

struct PasswordInfo {
    let lastSetDate: Date
    let daysUntilExpiration: Int
    let expiryDate: Date
    let isExpired: Bool
}

enum ADError: Error {
    case notConnected
    case userNotFound
    case invalidData
    case commandFailed(String)
}

class ActiveDirectoryManager {
    private let domainName = "BP-ITAKA"  // Twoja domena z skryptu
    private let maxPasswordAge = 30  // Dni
    private let warningThreshold = 7  // Ostrzeż od 7 dni
    
    /// Sprawdza połączenie z AD
    func checkADConnectivity() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = ["/Active Directory/\(domainName)/All Domains", "list", "/Users"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Pobiera informacje o haśle użytkownika
    func getPasswordInfo(for username: String) throws -> PasswordInfo {
        // Najpierw próba z AD
        if checkADConnectivity() {
            if let info = try? getPasswordInfoFromAD(username: username) {
                return info
            }
        }
        
        // Fallback do lokalnego Open Directory
        return try getPasswordInfoLocal(username: username)
    }
    
    /// Pobiera SMBPasswordLastSet z AD
    private func getPasswordInfoFromAD(username: String) throws -> PasswordInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = [
            "/Active Directory/\(domainName)/All Domains",
            "-read",
            "/Users/\(username)",
            "SMBPasswordLastSet"
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            throw ADError.commandFailed("dscl failed with code \(task.terminationStatus)")
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ADError.invalidData
        }
        
        // Parse: "SMBPasswordLastSet: 133123456789012345"
        guard let lastSetRaw = output
            .components(separatedBy: "SMBPasswordLastSet:")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let lastSetInt = Int64(lastSetRaw) else {
            throw ADError.invalidData
        }
        
        // Konwersja Windows FILETIME → UNIX timestamp
        let unixTimestamp = (lastSetInt / 10_000_000) - 11_644_473_600
        let lastSetDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))
        
        return calculateExpirationInfo(from: lastSetDate)
    }
    
    /// Fallback: lokalny passwordLastSetTime
    private func getPasswordInfoLocal(username: String) throws -> PasswordInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        task.arguments = [
            ".",
            "-read",
            "/Users/\(username)",
            "passwordLastSetTime"
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            throw ADError.userNotFound
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ADError.invalidData
        }
        
        // Parse timestamp lub data string
        guard let timeString = output
            .components(separatedBy: "passwordLastSetTime:")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ADError.invalidData
        }
        
        // Może być format: "01/15/2026 10:30:00" lub timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        
        let lastSetDate: Date
        if let date = formatter.date(from: timeString) {
            lastSetDate = date
        } else if let timestamp = Double(timeString) {
            lastSetDate = Date(timeIntervalSince1970: timestamp)
        } else {
            throw ADError.invalidData
        }
        
        return calculateExpirationInfo(from: lastSetDate)
    }
    
    /// Oblicza dni do wygaśnięcia
    private func calculateExpirationInfo(from lastSetDate: Date) -> PasswordInfo {
        let expiryDate = Calendar.current.date(
            byAdding: .day,
            value: maxPasswordAge,
            to: lastSetDate
        ) ?? lastSetDate
        
        let daysUntilExpiration = Calendar.current.dateComponents(
            [.day],
            from: Date(),
            to: expiryDate
        ).day ?? 0
        
        return PasswordInfo(
            lastSetDate: lastSetDate,
            daysUntilExpiration: daysUntilExpiration,
            expiryDate: expiryDate,
            isExpired: daysUntilExpiration <= 0
        )
    }
    
    /// Sprawdza czy trzeba pokazać ostrzeżenie
    func shouldShowWarning(passwordInfo: PasswordInfo) -> Bool {
        return passwordInfo.daysUntilExpiration <= warningThreshold
    }
}
