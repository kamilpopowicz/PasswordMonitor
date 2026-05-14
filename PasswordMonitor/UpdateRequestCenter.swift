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
    @Published var checkRequestID: UUID?

    func requestCheck() {
        checkRequestID = UUID()
    }
}
