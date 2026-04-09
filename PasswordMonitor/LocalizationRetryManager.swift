//
//  LocalizationRetryManager.swift
//  PasswordMonitor
//
//  Created by Codex on 08/04/2026.
//

import Foundation
import PasswordMonitorCore

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class LocalizationRetryManager {
    struct RetryResult {
        let attempted: Int
        let fixed: Int
        let remaining: Int
    }

    static let shared = LocalizationRetryManager()

    private let defaults = UserDefaults.standard
    private var delayedRetryTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func handleAppLaunch() {
        let languageCode = LanguageSettings.currentLanguageCode()
        Task {
            await runDelayedRetryIfDue(for: languageCode)
            await runDailyStartupRetryIfNeeded(for: languageCode)
        }
    }

    func pendingCount(for languageCode: String) -> Int {
        let pending = defaults.stringArray(forKey: pendingKey(languageCode)) ?? []
        return pending.count
    }

    func retryNow(for languageCode: String) async -> RetryResult {
        guard languageCode != "en" else {
            return RetryResult(attempted: 0, fixed: 0, remaining: 0)
        }
        let attempted = pendingCount(for: languageCode)
        guard attempted > 0 else {
            return RetryResult(attempted: 0, fixed: 0, remaining: 0)
        }
        let (fixed, remaining) = await retryPendingKeys(for: languageCode, reason: "manual")
        return RetryResult(attempted: attempted, fixed: fixed, remaining: remaining)
    }

    func recordProblematicKeys(_ keys: [String], for languageCode: String) {
        guard languageCode != "en" else { return }
        guard !keys.isEmpty else { return }

        var pending = Set(defaults.stringArray(forKey: pendingKey(languageCode)) ?? [])
        pending.formUnion(keys)
        defaults.set(Array(pending).sorted(), forKey: pendingKey(languageCode))
        Logger.shared.log("Queued problematic localization keys for retry: language=\(languageCode), count=\(pending.count)")
    }

    func scheduleOneHourRetry(for languageCode: String) {
        guard languageCode != "en" else { return }
        let pending = defaults.stringArray(forKey: pendingKey(languageCode)) ?? []
        guard !pending.isEmpty else { return }

        defaults.set(Date().addingTimeInterval(3600).timeIntervalSince1970, forKey: delayedDueKey(languageCode))
        defaults.set(false, forKey: delayedDoneKey(languageCode))

        delayedRetryTasks[languageCode]?.cancel()
        delayedRetryTasks[languageCode] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            await self?.runDelayedRetryIfDue(for: languageCode)
        }
    }

    private func runDelayedRetryIfDue(for languageCode: String) async {
        guard languageCode != "en" else { return }
        let pending = defaults.stringArray(forKey: pendingKey(languageCode)) ?? []
        guard !pending.isEmpty else { return }
        guard defaults.bool(forKey: delayedDoneKey(languageCode)) == false else { return }
        let due = defaults.double(forKey: delayedDueKey(languageCode))
        guard due > 0 else { return }
        guard Date().timeIntervalSince1970 >= due else { return }

        Logger.shared.log("Starting one-hour localization retry: language=\(languageCode), pending=\(pending.count)")
        await retryPendingKeys(for: languageCode, reason: "delayed_1h")
        defaults.set(true, forKey: delayedDoneKey(languageCode))
    }

    private func runDailyStartupRetryIfNeeded(for languageCode: String) async {
        guard languageCode != "en" else { return }
        let pending = defaults.stringArray(forKey: pendingKey(languageCode)) ?? []
        guard !pending.isEmpty else { return }

        let today = dayString(Date())
        let lastDay = defaults.string(forKey: startupDayKey(languageCode))
        guard lastDay != today else { return }

        defaults.set(today, forKey: startupDayKey(languageCode))
        Logger.shared.log("Starting daily startup localization retry: language=\(languageCode), pending=\(pending.count)")
        await retryPendingKeys(for: languageCode, reason: "startup_daily")
    }

    private func retryPendingKeys(for languageCode: String, reason: String) async -> (fixed: Int, remaining: Int) {
        guard await isAppleIntelligenceAvailable() else {
            Logger.shared.log("Skipping localization retry (\(reason)): Apple Intelligence unavailable")
            return (0, pendingCount(for: languageCode))
        }
        guard let baseStrings = loadBaseLocalizations() else {
            Logger.shared.log("Skipping localization retry (\(reason)): missing base localizations")
            return (0, pendingCount(for: languageCode))
        }

        let pendingArray = defaults.stringArray(forKey: pendingKey(languageCode)) ?? []
        var remaining = Set(pendingArray)
        guard !remaining.isEmpty else { return (0, 0) }

        var custom = LanguageSettings.loadCustomTranslations(for: languageCode) ?? [:]
        var fixedCount = 0

        for key in pendingArray {
            guard remaining.contains(key) else { continue }
            guard let source = baseStrings[key] else {
                remaining.remove(key)
                continue
            }

            var accepted: String?
            for attempt in 1...3 {
                guard #available(macOS 26.0, *) else { break }
                do {
                    let translated = try await translateText(
                        source,
                        to: languageCode,
                        key: key,
                        strict: attempt > 1
                    )
                    if shouldRetryTranslation(source: source, translated: translated) {
                        continue
                    }
                    if !hasCompatiblePlaceholders(source: source, translated: translated) {
                        continue
                    }
                    accepted = translated
                    break
                } catch {
                    continue
                }
            }

            guard let accepted else { continue }
            custom[key] = accepted
            remaining.remove(key)
            fixedCount += 1
        }

        LanguageSettings.saveCustomTranslations(custom, for: languageCode)
        defaults.set(Array(remaining).sorted(), forKey: pendingKey(languageCode))

        Logger.shared.log("Localization retry finished (\(reason)): language=\(languageCode), fixed=\(fixedCount), remaining=\(remaining.count)")

        if fixedCount > 0, languageCode == LanguageSettings.currentLanguageCode() {
            NotificationCenter.default.post(name: .appLanguageChanged, object: nil, userInfo: ["code": languageCode])
        }
        return (fixedCount, remaining.count)
    }

    private func pendingKey(_ languageCode: String) -> String {
        "localization_retry_pending_\(languageCode)"
    }

    private func delayedDueKey(_ languageCode: String) -> String {
        "localization_retry_delayed_due_\(languageCode)"
    }

    private func delayedDoneKey(_ languageCode: String) -> String {
        "localization_retry_delayed_done_\(languageCode)"
    }

    private func startupDayKey(_ languageCode: String) -> String {
        "localization_retry_startup_day_\(languageCode)"
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func loadBaseLocalizations() -> [String: String]? {
        var result: [String: String] = [:]

        if let stringsURL = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: "en"
        ),
           let dict = NSDictionary(contentsOf: stringsURL) as? [String: String] {
            result.merge(dict) { _, new in new }
        }

        if let stringsDictURL = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "stringsdict",
            subdirectory: nil,
            localization: "en"
        ),
           let data = try? Data(contentsOf: stringsDictURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let root = plist as? [String: Any] {
            for (key, value) in root {
                guard let entry = value as? [String: Any],
                      let valueNode = entry["value"] as? [String: Any] else { continue }
                if let other = valueNode["other"] as? String {
                    result[key] = other
                } else if let one = valueNode["one"] as? String {
                    result[key] = one
                }
            }
        }

        return result.isEmpty ? nil : result
    }

    private func hasCompatiblePlaceholders(source: String, translated: String) -> Bool {
        func tokens(_ text: String) -> [String] {
            let pattern = "%(?:#@[^@]+@|(?:\\d+\\$)?[-+ #0']*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?(?:hh|h|ll|l|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp%])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            return regex.matches(in: text, range: range).compactMap { match in
                guard match.range.location != NSNotFound else { return nil }
                let token = ns.substring(with: match.range)
                return token == "%%" ? nil : token
            }
        }

        func family(_ token: String) -> String {
            if token.hasPrefix("%#@"), token.hasSuffix("@") {
                return "plural"
            }
            guard let conversion = token.last else { return token }
            switch conversion {
            case "@":
                return "object"
            case "d", "i", "u", "o", "x", "X":
                return "int"
            case "f", "F", "e", "E", "g", "G", "a", "A":
                return "float"
            case "c", "C":
                return "char"
            case "s", "S":
                return "cstring"
            case "p":
                return "pointer"
            default:
                return token
            }
        }

        let sourceTokens = tokens(source)
        let translatedTokens = tokens(translated)
        guard sourceTokens.count == translatedTokens.count else { return false }

        for (lhs, rhs) in zip(sourceTokens, translatedTokens) {
            let left = family(lhs)
            let right = family(rhs)
            if left == right { continue }
            if (left == "plural" && right == "int") || (left == "int" && right == "plural") {
                continue
            }
            return false
        }
        return true
    }

    private func shouldRetryTranslation(source: String, translated: String) -> Bool {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let dst = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if dst.isEmpty { return true }
        if dst.caseInsensitiveCompare(src) == .orderedSame { return true }
        let lower = dst.lowercased()
        if lower.contains("no translation available") { return true }
        if lower.contains("translation unavailable") { return true }
        if dst.range(of: #"(?i)[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\d+\s*[\]\}\)]{1,2}|\bPH\s*[_-]?\s*\d+\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.contains("ui text key") { return true }
        if dst.range(of: #"[a-z0-9]+(?:_[a-z0-9]+){2,}"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private func sanitizeTranslatedText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned
    }

    private func protectPlaceholders(in text: String) -> (text: String, placeholders: [String]) {
        let pattern = "%(?:#@[^@]+@|(?:\\d+\\$)?[-+ #0']*(?:\\d+|\\*)?(?:\\.(?:\\d+|\\*))?(?:hh|h|ll|l|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp%])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }

        var placeholders: [String] = []
        var chunks: [String] = []
        var cursor = 0

        for match in matches {
            guard match.range.location != NSNotFound else { continue }
            if match.range.location > cursor {
                chunks.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let token = ns.substring(with: match.range)
            if token == "%%" {
                chunks.append(token)
            } else {
                let marker = "[[PH_\(placeholders.count)]]"
                placeholders.append(token)
                chunks.append(marker)
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            chunks.append(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }

        return (chunks.joined(), placeholders)
    }

    private func restorePlaceholders(in text: String, placeholders: [String]) -> String {
        var restored = text
        for (index, token) in placeholders.enumerated() {
            let pattern = #"(?i)[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\#(index)\s*[\]\}\)]{1,2}"#
            restored = restored.replacingOccurrences(of: pattern, with: token, options: .regularExpression)
        }
        let unmatchedPattern = #"(?i)[\[\{\(]{1,2}\s*PH\s*[_-]?\s*\d+\s*[\]\}\)]{1,2}|\bPH\s*[_-]?\s*\d+\b"#
        restored = restored.replacingOccurrences(
            of: unmatchedPattern,
            with: "",
            options: .regularExpression
        )
        if placeholders.isEmpty {
            restored = restored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return restored
    }

    private func splitText(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }
        var parts: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if current.count >= maxLength {
                parts.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        return parts
    }

    private func extractResponseText(from response: Any) -> String {
        if let string = extractPreferredString(from: response, depth: 0) {
            return string
        }
        return String(describing: response)
    }

    private func extractPreferredString(from value: Any, depth: Int) -> String? {
        if depth > 6 { return nil }
        if let string = value as? String {
            return string
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional, let child = mirror.children.first {
            return extractPreferredString(from: child.value, depth: depth + 1)
        }

        let preferredLabels: Set<String> = ["content", "message", "text", "value", "output", "response"]
        for child in mirror.children {
            if let label = child.label, preferredLabels.contains(label) {
                if let string = extractPreferredString(from: child.value, depth: depth + 1) {
                    return string
                }
            }
        }

        for child in mirror.children {
            if let string = extractPreferredString(from: child.value, depth: depth + 1) {
                return string
            }
        }

        return nil
    }

    private func isAppleIntelligenceAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                _ = try await session.respond(to: "Reply only with OK")
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    @available(macOS 26.0, *)
    private func translateText(_ text: String, to languageCode: String, key: String, strict: Bool) async throws -> String {
        do {
            let protected = protectPlaceholders(in: text)
            let session = LanguageModelSession()
            let strictClause = strict ? "You MUST translate to idiomatic \(languageCode). Never answer in English unless the text is a product name." : ""
            let prompt = """
            Translate this UI text to \(languageCode). \(strictClause)
            Keep placeholder markers like [[PH_0]] exactly unchanged.
            Preserve line breaks.
            Return ONLY the translated text, no quotes, no markdown.
            Text: \(protected.text)
            """
            let response = try await session.respond(to: prompt)
            let raw = extractResponseText(from: response)
            let sanitized = sanitizeTranslatedText(raw)
            return restorePlaceholders(in: sanitized, placeholders: protected.placeholders)
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("context window"),
               message.localizedCaseInsensitiveContains("exceeded") {
                let parts = splitText(text, maxLength: 120)
                var translatedParts: [String] = []
                translatedParts.reserveCapacity(parts.count)
                for part in parts {
                    let protected = protectPlaceholders(in: part)
                    let session = LanguageModelSession()
                    let strictClause = strict ? "You MUST translate to idiomatic \(languageCode). Never answer in English unless the text is a product name." : ""
                    let prompt = """
                    Translate this UI text to \(languageCode). \(strictClause)
                    Keep placeholder markers like [[PH_0]] exactly unchanged.
                    Preserve line breaks.
                    Return ONLY the translated text, no quotes, no markdown.
                    Text: \(protected.text)
                    """
                    let response = try await session.respond(to: prompt)
                    let raw = extractResponseText(from: response)
                    let sanitized = sanitizeTranslatedText(raw)
                    translatedParts.append(
                        restorePlaceholders(in: sanitized, placeholders: protected.placeholders)
                    )
                }
                return translatedParts.joined()
            }
            throw error
        }
    }
}
