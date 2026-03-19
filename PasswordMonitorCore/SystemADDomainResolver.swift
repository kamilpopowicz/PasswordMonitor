import Foundation

/// Reads the current Active Directory domain from macOS system configuration.
public struct SystemADDomainResolver {
    private static let dsconfigadPath = "/usr/sbin/dsconfigad"
    private static let dsclPath = "/usr/bin/dscl"
    private static let cacheTTL: TimeInterval = 60
    private static let nodeListCacheTTL: TimeInterval = 60

    private static var cachedDomain: (domain: String, expires: Date)?
    private static var cachedNodeList: (nodes: [String], expires: Date)?

    /// Returns the domain the machine is bound to, if any. The value is cached briefly to avoid repeating the system command.
    public static func currentDomain() -> String? {
        if let cached = cachedDomain, cached.expires > Date() {
            return cached.domain
        }

        guard let fetched = fetchDomainFromSystem() else {
            cachedDomain = nil
            return nil
        }

        cachedDomain = (domain: fetched, expires: Date().addingTimeInterval(cacheTTL))
        return fetched
    }

    /// Finds the DSCL node name that matches the configured domain (FQDN or short label).
    /// Falls back to `configuredDomain` if no node can be resolved.
    public static func adNodeName(for configuredDomain: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: dsclPath) else {
            return nil
        }

        guard let nodes = listActiveDirectoryNodes(), !nodes.isEmpty else {
            return nil
        }

        return matchingNode(for: configuredDomain, nodes: nodes)
    }

    static func matchingNode(for domain: String, nodes: [String]) -> String? {
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDomain.isEmpty else {
            return nil
        }

        let components = trimmedDomain.split(separator: ".")
        var candidates = Set<String>()
        candidates.insert(trimmedDomain)
        candidates.insert(trimmedDomain.lowercased())
        candidates.insert(trimmedDomain.uppercased())

        if let first = components.first {
            let base = String(first)
            candidates.insert(base)
            candidates.insert(base.lowercased())
            candidates.insert(base.uppercased())
        }

        if components.count > 1 {
            let withoutSuffix = components.dropLast().joined(separator: ".")
            candidates.insert(withoutSuffix)
            candidates.insert(withoutSuffix.lowercased())
            candidates.insert(withoutSuffix.uppercased())
        }

        for node in nodes {
            let normalizedNode = node.trimmingCharacters(in: .whitespacesAndNewlines)
            for candidate in candidates {
                if normalizedNode.caseInsensitiveCompare(candidate) == .orderedSame {
                    return node
                }
            }
        }

        return nil
    }

    private static func listActiveDirectoryNodes() -> [String]? {
        if let cached = cachedNodeList, cached.expires > Date() {
            return cached.nodes
        }

        guard FileManager.default.isExecutableFile(atPath: dsclPath) else {
            return nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: dsclPath)
        task.arguments = ["/Active Directory", "-list", "/"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "unknown"
            Logger.shared.logLocalized("log_ad_nodes_list_error %@ %d", errorMessage, task.terminationStatus)
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        let nodes = parseNodes(from: output)
        cachedNodeList = (nodes: nodes, expires: Date().addingTimeInterval(nodeListCacheTTL))

        let masked = nodes
            .map { maskNodeName($0) }
            .joined(separator: ", ")
        Logger.shared.logLocalized("log_ad_nodes_detected %@", masked.isEmpty ? "<none>" : masked)

        return nodes
    }

    private static func maskNodeName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return String(repeating: "*", count: max(1, trimmed.count)) }
        let first = trimmed.prefix(1)
        let last = trimmed.suffix(2)
        let maskCount = max(0, trimmed.count - 3)
        return "\(first)\(String(repeating: "*", count: maskCount))\(last)"
    }

    private static func parseNodes(from output: String) -> [String] {
        return output
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func fetchDomainFromSystem() -> String? {
        guard FileManager.default.isExecutableFile(atPath: dsconfigadPath) else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: dsconfigadPath)
        task.arguments = ["-show"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        return parseDomain(from: output)
    }

    static func parseDomain(from output: String) -> String? {
        for line in output.split(whereSeparator: { $0.isNewline }) {
            let components = line.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else { continue }
            let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if key.caseInsensitiveCompare("Active Directory Domain") == .orderedSame {
                let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                return value
            }
        }
        return nil
    }
}
