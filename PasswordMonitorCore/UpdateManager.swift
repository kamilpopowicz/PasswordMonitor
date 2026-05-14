//
//  UpdateManager.swift
//  PasswordMonitorCore
//
//  Created by Codex on 13/05/2026.
//

import Foundation
import CryptoKit

public struct PMUpdateConfiguration: Sendable {
    public let owner: String
    public let repository: String
    public let appBundleIdentifier: String
    public let appBundleName: String
    public let appZipAssetName: String
    public let manifestAssetName: String
    public let githubAPIBaseURL: URL
    public let publicKeyBase64: String

    public init(
        owner: String,
        repository: String,
        appBundleIdentifier: String,
        appBundleName: String,
        appZipAssetName: String,
        manifestAssetName: String,
        githubAPIBaseURL: URL,
        publicKeyBase64: String
    ) {
        self.owner = owner
        self.repository = repository
        self.appBundleIdentifier = appBundleIdentifier
        self.appBundleName = appBundleName
        self.appZipAssetName = appZipAssetName
        self.manifestAssetName = manifestAssetName
        self.githubAPIBaseURL = githubAPIBaseURL
        self.publicKeyBase64 = publicKeyBase64
    }

    public static let passwordMonitor = PMUpdateConfiguration(
        owner: "kamilpopowicz",
        repository: "PasswordMonitor",
        appBundleIdentifier: "popo.PasswordMonitor",
        appBundleName: "PasswordMonitor.app",
        appZipAssetName: "PasswordMonitor.app.zip",
        manifestAssetName: "PasswordMonitor.update-manifest.json",
        githubAPIBaseURL: URL(string: "https://api.github.com")!,
        publicKeyBase64: "M1zO9iVkkB7TNiFHBv1FAvT9ysEkBUZxNofAND96uJM="
    )

    public var releaseAPIURL: URL {
        githubAPIBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(owner)
            .appendingPathComponent(repository)
            .appendingPathComponent("releases")
            .appendingPathComponent("latest")
    }
}

private final class PMUpdateSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let allowedHosts: Set<String>

    init(allowedHosts: Set<String>) {
        self.allowedHosts = allowedHosts
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let host = request.url?.host?.lowercased(),
              allowedHosts.contains(host) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

public struct PMSemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public enum Component: Comparable, Hashable, Sendable {
        case numeric(Int)
        case text(String)

        public static func < (lhs: Component, rhs: Component) -> Bool {
            switch (lhs, rhs) {
            case let (.numeric(a), .numeric(b)):
                return a < b
            case (.numeric, .text):
                return false
            case (.text, .numeric):
                return true
            case let (.text(a), .text(b)):
                return a.localizedStandardCompare(b) == .orderedAscending
            }
        }
    }

    public let original: String
    public let coreComponents: [Int]
    public let prereleaseComponents: [Component]

    public init(_ string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PMUpdateError.invalidVersion(string)
        }

        let normalized = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let buildSplit = normalized.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let versionBody = buildSplit.first.map(String.init) ?? normalized
        let prereleaseSplit = versionBody.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = prereleaseSplit.first.map(String.init) ?? versionBody
        let prerelease = prereleaseSplit.count > 1 ? String(prereleaseSplit[1]) : ""

        let coreParts = core.split(separator: ".")
        let components = coreParts.compactMap { Int($0) }
        guard !components.isEmpty, components.count == coreParts.count else {
            throw PMUpdateError.invalidVersion(string)
        }

        self.original = normalized
        self.coreComponents = Self.trimmedTrailingZeros(components)
        self.prereleaseComponents = Self.parsePrerelease(prerelease)
    }

    public var description: String {
        let core = coreComponents.map(String.init).joined(separator: ".")
        guard !prereleaseComponents.isEmpty else { return core }
        let prerelease = prereleaseComponents.map { component -> String in
            switch component {
            case let .numeric(value):
                return String(value)
            case let .text(value):
                return value
            }
        }
        .joined(separator: ".")
        return "\(core)-\(prerelease)"
    }

    public static func < (lhs: PMSemanticVersion, rhs: PMSemanticVersion) -> Bool {
        let maxCount = max(lhs.coreComponents.count, rhs.coreComponents.count)
        for index in 0..<maxCount {
            let left = index < lhs.coreComponents.count ? lhs.coreComponents[index] : 0
            let right = index < rhs.coreComponents.count ? rhs.coreComponents[index] : 0
            if left == right { continue }
            return left < right
        }

        switch (lhs.prereleaseComponents.isEmpty, rhs.prereleaseComponents.isEmpty) {
        case (true, true):
            return false
        case (true, false):
            return false
        case (false, true):
            return true
        case (false, false):
            let maxPrereleaseCount = max(lhs.prereleaseComponents.count, rhs.prereleaseComponents.count)
            for index in 0..<maxPrereleaseCount {
                let left = index < lhs.prereleaseComponents.count ? lhs.prereleaseComponents[index] : .numeric(0)
                let right = index < rhs.prereleaseComponents.count ? rhs.prereleaseComponents[index] : .numeric(0)
                if left == right { continue }
                return left < right
            }
            return false
        }
    }

    private static func parsePrerelease(_ string: String) -> [Component] {
        guard !string.isEmpty else { return [] }
        return string.split(separator: ".").map { part in
            if let value = Int(part) {
                return .numeric(value)
            }
            return .text(String(part))
        }
    }

    private static func trimmedTrailingZeros(_ components: [Int]) -> [Int] {
        var result = components
        while result.count > 1, result.last == 0 {
            result.removeLast()
        }
        return result
    }
}

public struct PMUpdateManifest: Codable, Hashable, Sendable {
    public let version: String
    public let assetName: String
    public let assetSHA256: String
    public let bundleIdentifier: String
}

public struct PMSignedUpdateManifest: Codable, Hashable, Sendable {
    public let manifest: PMUpdateManifest
    public let signature: String
}

public struct PMUpdateCandidate: Hashable, Sendable {
    public let version: PMSemanticVersion
    public let releaseTag: String
    public let assetName: String
    public let assetURL: URL
    public let manifestURL: URL
    public let manifestName: String
    public let bundleIdentifier: String
    public let appBundleName: String

    public init(
        version: PMSemanticVersion,
        releaseTag: String,
        assetName: String,
        assetURL: URL,
        manifestURL: URL,
        manifestName: String,
        bundleIdentifier: String,
        appBundleName: String
    ) {
        self.version = version
        self.releaseTag = releaseTag
        self.assetName = assetName
        self.assetURL = assetURL
        self.manifestURL = manifestURL
        self.manifestName = manifestName
        self.bundleIdentifier = bundleIdentifier
        self.appBundleName = appBundleName
    }
}

public enum PMUpdateCheckResult: Sendable {
    case upToDate(localVersion: PMSemanticVersion, remoteVersion: PMSemanticVersion?)
    case updateAvailable(candidate: PMUpdateCandidate)
}

public enum PMUpdateError: LocalizedError, Equatable {
    case invalidVersion(String)
    case invalidGitHubResponse
    case remoteVersionUnavailable
    case remoteVersionNotNewer(local: String, remote: String)
    case missingExpectedAsset(String)
    case invalidManifestSignature
    case invalidManifestVersion
    case manifestBundleMismatch(expected: String, actual: String)
    case checksumMismatch(expected: String, actual: String)
    case invalidArchiveEntry(String)
    case archiveContainsSymlink(String)
    case archiveMissingAppBundle(String)
    case bundleIdentifierMismatch(expected: String, actual: String)
    case bundleVersionMismatch(expected: String, actual: String)
    case bundleSignatureInvalid(String)
    case insecureBundlePermissions(String)
    case installationFailed(String)
    case processFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .invalidVersion(version):
            return "Invalid version string: \(version)"
        case .invalidGitHubResponse:
            return "GitHub release response could not be parsed."
        case .remoteVersionUnavailable:
            return "The release does not expose a usable version."
        case let .remoteVersionNotNewer(local, remote):
            return "Remote version \(remote) is not newer than local version \(local)."
        case let .missingExpectedAsset(name):
            return "Expected release asset not found: \(name)"
        case .invalidManifestSignature:
            return "The update manifest signature is invalid."
        case .invalidManifestVersion:
            return "The update manifest version is invalid."
        case let .manifestBundleMismatch(expected, actual):
            return "Manifest bundle identifier \(actual) does not match expected \(expected)."
        case let .checksumMismatch(expected, actual):
            return "Checksum mismatch. Expected \(expected), got \(actual)."
        case let .invalidArchiveEntry(entry):
            return "Archive entry is not allowed: \(entry)"
        case let .archiveContainsSymlink(path):
            return "Archive contains a symlink: \(path)"
        case let .archiveMissingAppBundle(name):
            return "Archive does not contain the expected app bundle: \(name)"
        case let .bundleIdentifierMismatch(expected, actual):
            return "Installed bundle identifier \(actual) does not match expected \(expected)."
        case let .bundleVersionMismatch(expected, actual):
            return "Installed bundle version \(actual) does not match expected \(expected)."
        case let .bundleSignatureInvalid(path):
            return "Installed bundle failed code signature verification: \(path)"
        case let .insecureBundlePermissions(path):
            return "Installed bundle contains insecure permissions: \(path)"
        case let .installationFailed(message):
            return "Installation failed: \(message)"
        case let .processFailed(message):
            return "Command failed: \(message)"
        case .cancelled:
            return "Update cancelled."
        }
    }
}

public enum PMUpdateArchiveValidator {
    public static func validateArchiveEntries(_ entries: [String], expectedAppName: String) throws {
        let trimmedEntries = entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedEntries.isEmpty else {
            throw PMUpdateError.archiveMissingAppBundle(expectedAppName)
        }

        var rootComponent: String?

        for rawEntry in trimmedEntries {
            let entry = rawEntry.hasSuffix("/") ? String(rawEntry.dropLast()) : rawEntry
            guard !entry.hasPrefix("/") else {
                throw PMUpdateError.invalidArchiveEntry(rawEntry)
            }
            guard !entry.contains("..") else {
                throw PMUpdateError.invalidArchiveEntry(rawEntry)
            }

            let components = entry.split(separator: "/").map(String.init)
            guard !components.isEmpty, !components.contains("."), !components.contains(""), !components.contains(where: { $0 == ".." }) else {
                throw PMUpdateError.invalidArchiveEntry(rawEntry)
            }

            if let currentRoot = rootComponent {
                guard currentRoot == components[0] else {
                    throw PMUpdateError.invalidArchiveEntry(rawEntry)
                }
            } else {
                rootComponent = components[0]
            }
        }

        guard rootComponent == expectedAppName else {
            throw PMUpdateError.archiveMissingAppBundle(expectedAppName)
        }
    }

    public static func validateNoSymlinks(in bundleURL: URL, fileManager: FileManager = .default) throws {
        let enumerator = fileManager.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: [],
            errorHandler: nil
        )

        while let itemURL = enumerator?.nextObject() as? URL {
            let values = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw PMUpdateError.archiveContainsSymlink(itemURL.path)
            }
        }
    }

    public static func validatePermissions(in bundleURL: URL, fileManager: FileManager = .default) throws {
        let enumerator = fileManager.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: nil
        )

        var urls: [URL] = [bundleURL]
        while let itemURL = enumerator?.nextObject() as? URL {
            urls.append(itemURL)
        }

        for itemURL in urls {
            let attributes = try fileManager.attributesOfItem(atPath: itemURL.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard permissions != 0 else { continue }
            let groupWritable = permissions & 0o020 != 0
            let otherWritable = permissions & 0o002 != 0
            if groupWritable || otherWritable {
                throw PMUpdateError.insecureBundlePermissions(itemURL.path)
            }
        }
    }
}

public final class PMUpdateService {
    public struct GitHubRelease: Decodable, Sendable {
        public struct Asset: Decodable, Sendable {
            public let name: String
            public let apiURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case apiURL = "url"
            }
        }

        public let tagName: String
        public let assets: [Asset]
    }

    private let configuration: PMUpdateConfiguration
    private let session: URLSession
    private let fileManager: FileManager
    private let sessionDelegate: PMUpdateSessionDelegate

    public init(
        configuration: PMUpdateConfiguration = .passwordMonitor,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager

        let allowedHosts: Set<String> = [
            "api.github.com",
            "github.com",
            "objects.githubusercontent.com",
            "release-assets.githubusercontent.com",
            "githubusercontent.com"
        ]
        let delegate = PMUpdateSessionDelegate(allowedHosts: allowedHosts)
        self.sessionDelegate = delegate

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieAcceptPolicy = .never
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.timeoutIntervalForRequest = 30
        sessionConfiguration.timeoutIntervalForResource = 120

        self.session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
    }

    public func checkForUpdate(currentVersion: String) async throws -> PMUpdateCheckResult {
        let localVersion = try PMSemanticVersion(currentVersion)
        let release = try await fetchLatestRelease()
        guard let remoteVersion = try remoteVersion(from: release) else {
            throw PMUpdateError.remoteVersionUnavailable
        }

        guard remoteVersion > localVersion else {
            return .upToDate(localVersion: localVersion, remoteVersion: remoteVersion)
        }

        let candidate = try makeCandidate(from: release, version: remoteVersion)
        return .updateAvailable(candidate: candidate)
    }

    public func installUpdate(
        candidate: PMUpdateCandidate,
        currentAppURL: URL = Bundle.main.bundleURL,
        restartHandler: @escaping @Sendable () -> Void = {}
    ) async throws {
        let manifestData = try await downloadData(from: candidate.manifestURL)
        let signedManifest = try JSONDecoder().decode(PMSignedUpdateManifest.self, from: manifestData)
        try validateSignedManifest(signedManifest)

        let manifest = signedManifest.manifest
        let manifestVersion = try PMSemanticVersion(manifest.version)
        guard manifestVersion == candidate.version else {
            throw PMUpdateError.invalidManifestVersion
        }
        guard manifest.assetName == candidate.assetName else {
            throw PMUpdateError.missingExpectedAsset(candidate.assetName)
        }
        guard manifest.bundleIdentifier == candidate.bundleIdentifier else {
            throw PMUpdateError.manifestBundleMismatch(expected: candidate.bundleIdentifier, actual: manifest.bundleIdentifier)
        }

        let zipURL = try await downloadFile(from: candidate.assetURL)
        defer { try? fileManager.removeItem(at: zipURL) }

        let checksum = try sha256Hex(for: zipURL)
        guard checksum.caseInsensitiveCompare(manifest.assetSHA256) == .orderedSame else {
            throw PMUpdateError.checksumMismatch(expected: manifest.assetSHA256, actual: checksum)
        }

        let stagingRoot = try makeStagingDirectory(for: currentAppURL)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try validateZip(at: zipURL, expectedAppName: candidate.appBundleName)
        try extractZip(at: zipURL, to: stagingRoot)

        let stagedAppURL = stagingRoot.appendingPathComponent(candidate.appBundleName)
        guard fileManager.fileExists(atPath: stagedAppURL.path) else {
            throw PMUpdateError.archiveMissingAppBundle(candidate.appBundleName)
        }

        try PMUpdateArchiveValidator.validateNoSymlinks(in: stagedAppURL, fileManager: fileManager)
        try PMUpdateArchiveValidator.validatePermissions(in: stagedAppURL, fileManager: fileManager)
        try validateCodeSignature(at: stagedAppURL)
        try validateInstalledBundle(
            at: stagedAppURL,
            expectedBundleIdentifier: candidate.bundleIdentifier,
            expectedVersion: candidate.version
        )

        try replaceInstalledBundle(
            currentAppURL: currentAppURL,
            with: stagedAppURL,
            stagingRoot: stagingRoot
        )

        restartHandler()
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: configuration.releaseAPIURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PasswordMonitorUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw PMUpdateError.invalidGitHubResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw PMUpdateError.invalidGitHubResponse
        }
    }

    private func remoteVersion(from release: GitHubRelease) throws -> PMSemanticVersion? {
        let tag = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return nil }
        let cleanedTag = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return try PMSemanticVersion(cleanedTag)
    }

    private func makeCandidate(from release: GitHubRelease, version: PMSemanticVersion) throws -> PMUpdateCandidate {
        guard let asset = release.assets.first(where: { $0.name == configuration.appZipAssetName }) else {
            throw PMUpdateError.missingExpectedAsset(configuration.appZipAssetName)
        }
        guard let manifest = release.assets.first(where: { $0.name == configuration.manifestAssetName }) else {
            throw PMUpdateError.missingExpectedAsset(configuration.manifestAssetName)
        }

        return PMUpdateCandidate(
            version: version,
            releaseTag: release.tagName,
            assetName: asset.name,
            assetURL: asset.apiURL,
            manifestURL: manifest.apiURL,
            manifestName: manifest.name,
            bundleIdentifier: configuration.appBundleIdentifier,
            appBundleName: configuration.appBundleName
        )
    }

    func validateSignedManifest(_ signedManifest: PMSignedUpdateManifest) throws {
        let manifest = signedManifest.manifest
        let payloadData = try Self.manifestSigningPayload(for: manifest)
        guard let publicKeyData = Data(base64Encoded: configuration.publicKeyBase64) else {
            throw PMUpdateError.invalidManifestSignature
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard let signatureData = Data(base64Encoded: signedManifest.signature) else {
            throw PMUpdateError.invalidManifestSignature
        }
        guard publicKey.isValidSignature(signatureData, for: payloadData) else {
            throw PMUpdateError.invalidManifestSignature
        }
    }

    static func manifestSigningPayload(for manifest: PMUpdateManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifestData = try encoder.encode(manifest)
        var payload = Data("PasswordMonitorUpdateManifest/v1\n".utf8)
        payload.append(manifestData)
        return payload
    }

    private func downloadData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("PasswordMonitorUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw PMUpdateError.processFailed("download data failed for \(url.absoluteString)")
        }
        return data
    }

    private func downloadFile(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("PasswordMonitorUpdater/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (tempURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw PMUpdateError.processFailed("download file failed for \(url.absoluteString)")
        }
        return tempURL
    }

    private func validateZip(at zipURL: URL, expectedAppName: String) throws {
        let entries = try runCommand(
            "/usr/bin/unzip",
            arguments: ["-Z1", zipURL.path]
        )
        let lines = entries
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        try PMUpdateArchiveValidator.validateArchiveEntries(lines, expectedAppName: expectedAppName)
    }

    private func extractZip(at zipURL: URL, to stagingRoot: URL) throws {
        _ = try runCommand(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", "--sequesterRsrc", "--keepParent", zipURL.path, stagingRoot.path]
        )
    }

    private func validateInstalledBundle(
        at bundleURL: URL,
        expectedBundleIdentifier: String,
        expectedVersion: PMSemanticVersion
    ) throws {
        guard let bundle = Bundle(url: bundleURL) else {
            throw PMUpdateError.archiveMissingAppBundle(bundleURL.lastPathComponent)
        }

        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        guard bundleIdentifier == expectedBundleIdentifier else {
            throw PMUpdateError.bundleIdentifierMismatch(
                expected: expectedBundleIdentifier,
                actual: bundleIdentifier
            )
        }

        let bundleVersionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let bundleVersion = try PMSemanticVersion(bundleVersionString)
        guard bundleVersion == expectedVersion else {
            throw PMUpdateError.bundleVersionMismatch(
                expected: expectedVersion.description,
                actual: bundleVersion.description
            )
        }
    }

    private func validateCodeSignature(at bundleURL: URL) throws {
        _ = try runCommand(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", "--verbose=0", bundleURL.path]
        )
    }

    private func makeStagingDirectory(for currentAppURL: URL) throws -> URL {
        let parent = currentAppURL.deletingLastPathComponent()
        let directoryName = ".\(currentAppURL.deletingPathExtension().lastPathComponent).update-\(UUID().uuidString)"
        let url = parent.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func replaceInstalledBundle(
        currentAppURL: URL,
        with stagedAppURL: URL,
        stagingRoot: URL
    ) throws {
        let backupURL = currentAppURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(currentAppURL.deletingPathExtension().lastPathComponent).backup-\(UUID().uuidString).app")

        try fileManager.moveItem(at: currentAppURL, to: backupURL)
        do {
            try fileManager.moveItem(at: stagedAppURL, to: currentAppURL)
        } catch {
            try? fileManager.moveItem(at: backupURL, to: currentAppURL)
            throw PMUpdateError.installationFailed(error.localizedDescription)
        }

        try? fileManager.removeItem(at: backupURL)
        try? fileManager.removeItem(at: stagingRoot)
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 128 * 1024)
            guard let data, !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func runCommand(_ executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw PMUpdateError.processFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PMUpdateError.processFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}
