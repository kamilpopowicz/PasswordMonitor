#!/usr/bin/env swift

import Foundation
import CryptoKit

struct PMUpdateManifest: Codable {
    let version: String
    let assetName: String
    let assetSHA256: String
    let bundleIdentifier: String
    let signingKeyID: String
    let urgency: String
}

struct PMSignedUpdateManifest: Codable {
    let manifest: PMUpdateManifest
    let signature: String
}

struct Arguments {
    let version: String
    let assetName: String
    let bundleIdentifier: String
    let assetSHA256: String
    let signingKeyID: String
    let urgency: String
    let outputURL: URL
}

enum ManifestGenerationError: LocalizedError {
    case missingValue(String)
    case invalidBase64Key
    case invalidOutputURL

    var errorDescription: String? {
        switch self {
        case let .missingValue(name):
            return "Missing required value for \(name)."
        case .invalidBase64Key:
            return "UPDATE_MANIFEST_PRIVATE_KEY_BASE64 is invalid."
        case .invalidOutputURL:
            return "Output path is invalid."
        }
    }
}

func parseArguments() throws -> Arguments {
    var version: String?
    var assetName: String?
    var bundleIdentifier: String?
    var assetSHA256: String?
    var signingKeyID: String?
    var urgency = "normal"
    var outputPath: String?

    var iterator = Array(CommandLine.arguments.dropFirst()).makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--version":
            version = iterator.next()
        case "--asset-name":
            assetName = iterator.next()
        case "--bundle-id":
            bundleIdentifier = iterator.next()
        case "--sha256":
            assetSHA256 = iterator.next()
        case "--key-id":
            signingKeyID = iterator.next()
        case "--urgency":
            urgency = iterator.next() ?? "normal"
        case "--output":
            outputPath = iterator.next()
        case "--help", "-h":
            print("""
            Usage:
              generate_update_manifest.swift --version <version> --asset-name <name> --bundle-id <bundle-id> --sha256 <sha256> --key-id <key-id> [--urgency normal|critical] --output <path>
            """)
            exit(0)
        default:
            continue
        }
    }

    guard let version, !version.isEmpty else { throw ManifestGenerationError.missingValue("--version") }
    guard let assetName, !assetName.isEmpty else { throw ManifestGenerationError.missingValue("--asset-name") }
    guard let bundleIdentifier, !bundleIdentifier.isEmpty else { throw ManifestGenerationError.missingValue("--bundle-id") }
    guard let assetSHA256, !assetSHA256.isEmpty else { throw ManifestGenerationError.missingValue("--sha256") }
    guard let signingKeyID, !signingKeyID.isEmpty else { throw ManifestGenerationError.missingValue("--key-id") }
    guard let outputPath, !outputPath.isEmpty else { throw ManifestGenerationError.missingValue("--output") }

    let outputURL = URL(fileURLWithPath: outputPath)
    guard outputURL.isFileURL else { throw ManifestGenerationError.invalidOutputURL }

    return Arguments(
        version: version,
        assetName: assetName,
        bundleIdentifier: bundleIdentifier,
        assetSHA256: assetSHA256,
        signingKeyID: signingKeyID,
        urgency: urgency == "critical" ? "critical" : "normal",
        outputURL: outputURL
    )
}

func manifestSigningPayload(for manifest: PMUpdateManifest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let manifestData = try encoder.encode(manifest)
    var payload = Data("PasswordMonitorUpdateManifest/v1\n".utf8)
    payload.append(manifestData)
    return payload
}

do {
    let arguments = try parseArguments()
    guard let privateKeyBase64 = ProcessInfo.processInfo.environment["UPDATE_MANIFEST_PRIVATE_KEY_BASE64"],
          let privateKeyData = Data(base64Encoded: privateKeyBase64) else {
        throw ManifestGenerationError.invalidBase64Key
    }

    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
    let manifest = PMUpdateManifest(
        version: arguments.version,
        assetName: arguments.assetName,
        assetSHA256: arguments.assetSHA256,
        bundleIdentifier: arguments.bundleIdentifier,
        signingKeyID: arguments.signingKeyID,
        urgency: arguments.urgency
    )
    let payload = try manifestSigningPayload(for: manifest)
    let signature = try privateKey.signature(for: payload).base64EncodedString()
    let signedManifest = PMSignedUpdateManifest(manifest: manifest, signature: signature)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let outputData = try encoder.encode(signedManifest)

    let outputDirectory = arguments.outputURL.deletingLastPathComponent()
    if !outputDirectory.path.isEmpty {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }
    try outputData.write(to: arguments.outputURL, options: [.atomic])
} catch {
    FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8) ?? Data())
    exit(1)
}
