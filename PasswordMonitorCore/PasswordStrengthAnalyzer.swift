//
//  PasswordStrengthAnalyzer.swift
//  PasswordMonitorCore
//
//  Created by Codex on 21/05/2026.
//

import Foundation

public enum PasswordStrengthLevel: Int, CaseIterable {
    case veryWeak = 0
    case weak = 1
    case fair = 2
    case strong = 3
    case excellent = 4
}

public struct PasswordStrength: Equatable {
    public let level: PasswordStrengthLevel
    public let score: Int
    public let feedback: [String]

    public init(level: PasswordStrengthLevel, score: Int, feedback: [String]) {
        self.level = level
        self.score = score
        self.feedback = feedback
    }
}

public enum PasswordStrengthAnalyzer {
    public static let minimumUsefulLength = 8
    public static let passphraseLength = 16
    public static let excellentLength = 20

    private static let commonPasswords: Set<String> = [
        "password",
        "password1",
        "password123",
        "qwerty",
        "qwerty123",
        "admin",
        "administrator",
        "welcome",
        "welcome1",
        "letmein",
        "changeme",
        "monkey",
        "dragon",
        "football",
        "iloveyou"
    ]

    private static let keyboardSequences = [
        "qwerty",
        "asdf",
        "zxcv",
        "1234",
        "2345",
        "3456",
        "4567",
        "5678",
        "6789",
        "abcd",
        "bcde",
        "cdef"
    ]

    public static func analyze(_ password: String, userInputs: [String] = []) -> PasswordStrength {
        let normalized = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return PasswordStrength(
                level: .veryWeak,
                score: 0,
                feedback: ["Enter a new password."]
            )
        }

        let lowercased = normalized.lowercased()
        var score = lengthScore(for: normalized)
        var feedback: [String] = []

        if normalized.count < minimumUsefulLength {
            score -= 2
            feedback.append("Use at least 8 characters.")
        }

        if commonPasswords.contains(lowercased) {
            score -= 4
            feedback.append("Avoid common passwords.")
        }

        if containsUserInput(lowercasedPassword: lowercased, userInputs: userInputs) {
            score -= 2
            feedback.append("Avoid using your name, domain, or app name.")
        }

        if containsKeyboardSequence(lowercased) {
            score -= 1
            feedback.append("Avoid keyboard sequences.")
        }

        if containsRepeatedPattern(lowercased) {
            score -= 1
            feedback.append("Avoid repeated patterns.")
        }

        if containsLikelyYearOrDate(lowercased) {
            score -= 1
            feedback.append("Avoid years or dates.")
        }

        if hasMultipleCharacterClasses(normalized) {
            score += 1
        }

        if looksLikePassphrase(normalized) {
            score += 1
            feedback.append("Passphrases are easier to remember and harder to guess.")
        }

        let clampedScore = max(0, min(4, score))
        if feedback.isEmpty {
            feedback.append(clampedScore >= 3 ? "This password looks strong." : "Make it longer or less predictable.")
        }

        return PasswordStrength(
            level: PasswordStrengthLevel(rawValue: clampedScore) ?? .veryWeak,
            score: clampedScore,
            feedback: feedback
        )
    }

    private static func lengthScore(for password: String) -> Int {
        switch password.count {
        case 0..<minimumUsefulLength:
            return 0
        case minimumUsefulLength..<12:
            return 1
        case 12..<passphraseLength:
            return 2
        case passphraseLength..<excellentLength:
            return 3
        default:
            return 4
        }
    }

    private static func containsUserInput(lowercasedPassword: String, userInputs: [String]) -> Bool {
        userInputs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 3 }
            .contains { lowercasedPassword.contains($0) }
    }

    private static func containsKeyboardSequence(_ password: String) -> Bool {
        keyboardSequences.contains { password.contains($0) }
    }

    private static func containsRepeatedPattern(_ password: String) -> Bool {
        let characters = Array(password)
        guard characters.count >= 4 else { return false }

        for index in characters.indices.dropFirst(3) {
            if characters[index] == characters[index - 1],
               characters[index] == characters[index - 2],
               characters[index] == characters[index - 3] {
                return true
            }
        }

        return password.range(of: #"(.{2,4})\1{1,}"#, options: .regularExpression) != nil
    }

    private static func containsLikelyYearOrDate(_ password: String) -> Bool {
        password.range(of: #"(19|20)\d{2}"#, options: .regularExpression) != nil ||
            password.range(of: #"\d{1,2}[-_/]\d{1,2}[-_/]\d{2,4}"#, options: .regularExpression) != nil
    }

    private static func hasMultipleCharacterClasses(_ password: String) -> Bool {
        let hasLetter = password.rangeOfCharacter(from: .letters) != nil
        let hasDigit = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
        return [hasLetter, hasDigit, hasSymbol].filter { $0 }.count >= 2
    }

    private static func looksLikePassphrase(_ password: String) -> Bool {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_.,"))
        let words = password
            .components(separatedBy: separators)
            .filter { $0.count >= 3 }
        return password.count >= passphraseLength && words.count >= 3
    }
}
