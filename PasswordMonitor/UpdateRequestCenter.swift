//
//  UpdateRequestCenter.swift
//  PasswordMonitor
//
//  Created by Codex on 14/05/2026.
//

import Foundation
import Combine

@MainActor
final class UpdateRequestCenter: ObservableObject {
    enum RequestKind: Equatable {
        case checkOnly
        case startDetectedUpdate
        case criticalUpdate
    }

    struct Request: Identifiable {
        let id = UUID()
        let kind: RequestKind
        let createdAt = Date()
    }

    private let duplicateWindow: TimeInterval = 2
    private var lastRequestKind: RequestKind?
    private var lastRequestAt: Date?

    @Published var checkRequestID: UUID?
    @Published var request: Request?

    func requestCheck() {
        checkRequestID = UUID()
        request = Request(kind: .checkOnly)
    }

    func requestStartDetectedUpdate() {
        requestInstall(kind: .startDetectedUpdate)
    }

    func requestCriticalUpdate() {
        requestInstall(kind: .criticalUpdate)
    }

    private func requestInstall(kind: RequestKind) {
        let now = Date()
        if lastRequestKind == kind,
           let lastRequestAt,
           now.timeIntervalSince(lastRequestAt) < duplicateWindow {
            return
        }
        lastRequestKind = kind
        lastRequestAt = now
        request = Request(kind: kind)
    }
}
