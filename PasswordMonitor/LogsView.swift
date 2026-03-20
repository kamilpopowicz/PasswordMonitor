//
//  LogsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 09/02/2026.
//

import SwiftUI
import AppKit
import PasswordMonitorCore

struct LogsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var logStore = LogStore()
    @State private var searchText = ""
    @State private var selectedLevel: Logger.Level? = nil
    @State private var isFollowingLatest = true
    @State private var scrollToBottomToken = UUID()
    @State private var showSearchField = false
    @State private var searchFocusToken = UUID()
    private let searchColumnWidth: CGFloat = 260
    private let searchButtonSpacing: CGFloat = 6
    private let levelsColumnWidth: CGFloat = 430

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Button("logs_now") {
                            isFollowingLatest = true
                            scrollToBottomToken = UUID()
                        }
                        .pmButton(role: isFollowingLatest ? .primary : .secondary)

                        Button("logs_clear") {
                            logStore.clear()
                        }
                        .pmButton(role: .destructive)

                        Button("logs_reload") {
                            logStore.reload()
                        }
                        .pmButton()

                        Button("logs_reveal") {
                            logStore.revealInFinder()
                        }
                        .pmButton()

                        Button("logs_export") {
                            logStore.share()
                        }
                        .pmButton()
                    }

                    Spacer()

                    HStack(spacing: searchButtonSpacing) {
                        SearchField(
                            text: $searchText,
                            placeholder: String(localized: "logs_search_placeholder"),
                            isDark: themeManager.isDarkAppearance,
                            isVisible: showSearchField,
                            focusToken: $searchFocusToken
                        )
                        .frame(width: showSearchField ? (searchColumnWidth - 32 - searchButtonSpacing) : 0)
                        .opacity(showSearchField ? 1 : 0)
                        .clipped()
                        .animation(.easeInOut(duration: 0.18), value: showSearchField)
                        .allowsHitTesting(showSearchField)

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showSearchField.toggle()
                                if showSearchField {
                                    searchFocusToken = UUID()
                                } else {
                                    searchText = ""
                                }
                            }
                        } label: {
                            Image(systemName: showSearchField ? "xmark" : "magnifyingglass")
                        }
                        .pmButton(role: .secondary, size: .compact)
                        .help(showSearchField ? String(localized: "logs_search_close") : String(localized: "logs_search"))
                    }
                    .frame(width: searchColumnWidth, alignment: .trailing)
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            (Text("logs_level_filter") + Text(":"))
                                .font(.caption)
                                .foregroundColor(PMTheme.textSecondary)
                            Picker("", selection: $selectedLevel) {
                                Text("logs_level_all").tag(Logger.Level?.none)
                                Text("logs_level_info").tag(Logger.Level?.some(.info))
                                Text("logs_level_warning").tag(Logger.Level?.some(.warning))
                                Text("logs_level_error").tag(Logger.Level?.some(.error))
                                Text("logs_level_debug").tag(Logger.Level?.some(.debug))
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: levelsColumnWidth - 80, alignment: .leading)
                        }

                        HStack(spacing: 8) {
                            (Text("logs_legend") + Text(":"))
                                .font(.caption)
                                .foregroundColor(PMTheme.textSecondary)
                            LegendDot(color: PMTheme.textPrimary, labelKey: "logs_level_info")
                            LegendDot(color: PMTheme.warning, labelKey: "logs_level_warning")
                            LegendDot(color: PMTheme.danger, labelKey: "logs_level_error")
                            LegendDot(color: PMTheme.textMuted, labelKey: "logs_level_debug")
                        }
                    }
                    .frame(width: levelsColumnWidth, alignment: .leading)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            (Text("logs_refresh_label") + Text(":"))
                                .font(.caption)
                                .foregroundColor(PMTheme.textSecondary)
                                .padding(.trailing, 10)
                            Picker("", selection: $logStore.refreshMode) {
                                Text("logs_refresh_immediate").tag(LogStore.RefreshMode.immediate)
                                Text("logs_refresh_1m").tag(LogStore.RefreshMode.oneMinute)
                                Text("logs_refresh_5m").tag(LogStore.RefreshMode.fiveMinutes)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220, alignment: .trailing)
                        }

                        Text("logs_privacy_notice")
                            .font(.caption)
                            .foregroundColor(PMTheme.textSecondary)
                            .italic()
                            .multilineTextAlignment(.trailing)
                            .frame(width: searchColumnWidth, alignment: .trailing)
                    }
                }
            }
            .padding()

            Divider()

            ZStack {
                if themeManager.isApplyingTheme {
                    LogsThemePlaceholder()
                } else {
                    LogTextView(
                        attributedText: attributedContent(),
                        isFollowingLatest: $isFollowingLatest,
                        scrollToBottomToken: $scrollToBottomToken,
                        isDark: themeManager.isDarkAppearance
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(PMTheme.fieldBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(PMTheme.fieldStroke, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if logStore.isLoading {
                    LoadingOverlay()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)

            VStack(spacing: 2) {
                Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
            }
            .font(.caption2)
            .foregroundColor(PMTheme.textSecondary)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            logStore.start()
            appState.windowOpened()
            isFollowingLatest = true
            scrollToBottomToken = UUID()
            DispatchQueue.main.async {
                appState.activateApp()
            }
        }
        .onDisappear {
            logStore.stop()
            appState.windowClosed()
        }
        .onChange(of: logStore.content) { _, _ in
            if isFollowingLatest {
                scrollToBottomToken = UUID()
            }
        }
        .onChange(of: logStore.refreshMode) { _, newValue in
            logStore.setRefreshMode(newValue)
        }
    }

    private var filteredContent: String {
        let lines = logStore.content.split(separator: "\n", omittingEmptySubsequences: false)
        let levelToken = selectedLevel.map { "[\($0.rawValue)]" }

        let filtered = lines.filter { line in
            let matchesLevel = levelToken.map { line.contains($0) } ?? true
            let matchesSearch = searchText.isEmpty ? true : line.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
        return filtered.joined(separator: "\n")
    }

    private func attributedContent() -> NSAttributedString {
        if filteredContent.isEmpty {
            return NSAttributedString(
                string: String(localized: "logs_empty"),
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    .foregroundColor: NSColor(PMTheme.textSecondary)
                ]
            )
        }

        let lines = filteredContent.split(separator: "\n", omittingEmptySubsequences: false)
        let result = NSMutableAttributedString()
        for (index, lineSub) in lines.enumerated() {
            let line = String(lineSub)
            let color: NSColor
            if line.contains("[ERROR]") { color = NSColor(PMTheme.danger) }
            else if line.contains("[WARN]") { color = NSColor(PMTheme.warning) }
            else if line.contains("[DEBUG]") { color = NSColor(PMTheme.textMuted) }
            else { color = NSColor(PMTheme.textPrimary) }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: color
            ]
            result.append(NSAttributedString(string: line, attributes: attributes))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        return result
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isDark: Bool
    let isVisible: Bool
    @Binding var focusToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = true
        field.focusRingType = .none
        field.controlSize = .small
        field.drawsBackground = true
        context.coordinator.field = field
        applyAppearance(field)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        applyAppearance(nsView)

        if isVisible, context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            nsView.window?.makeFirstResponder(nsView)
        } else if !isVisible, nsView.window?.firstResponder == nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    private func applyAppearance(_ field: NSSearchField) {
        if isDark {
            field.backgroundColor = PMTheme.resolvedFieldBackground(isDark: true)
            field.textColor = PMTheme.resolvedTextPrimary(isDark: true)
            field.appearance = NSAppearance(named: .darkAqua)
        } else {
            field.backgroundColor = PMTheme.resolvedFieldBackground(isDark: false)
            field.textColor = PMTheme.resolvedTextPrimary(isDark: false)
            field.appearance = NSAppearance(named: .aqua)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        weak var field: NSSearchField?
        var lastFocusToken = UUID()

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}

private struct LogTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    @Binding var isFollowingLatest: Bool
    @Binding var scrollToBottomToken: UUID
    let isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFollowingLatest: $isFollowingLatest)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = isDark ? NSColor(PMTheme.textPrimary) : NSColor(PMTheme.textPrimary)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textColor = isDark ? NSColor(PMTheme.textPrimary) : NSColor(PMTheme.textPrimary)
        textView.insertionPointColor = isDark ? NSColor(PMTheme.textPrimary) : NSColor(PMTheme.textPrimary)
        textView.drawsBackground = false

        if textView.textStorage?.length != attributedText.length ||
            textView.attributedString() != attributedText {
            textView.textStorage?.setAttributedString(attributedText)
        }

        if context.coordinator.lastScrollToken != scrollToBottomToken {
            context.coordinator.lastScrollToken = scrollToBottomToken
            scrollToBottom(nsView)
        } else if isFollowingLatest {
            scrollToBottom(nsView)
        }
    }

    private func scrollToBottom(_ scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let length = textView.string.count
        if length > 0 {
            textView.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
        } else {
            scrollView.contentView.scroll(to: .zero)
        }
    }

    final class Coordinator: NSObject {
        @Binding var isFollowingLatest: Bool
        weak var scrollView: NSScrollView?
        var lastScrollToken = UUID()

        init(isFollowingLatest: Binding<Bool>) {
            _isFollowingLatest = isFollowingLatest
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard let scrollView else { return }
            guard let textView = scrollView.documentView as? NSTextView else { return }
            let visible = scrollView.contentView.documentVisibleRect
            let maxY = textView.bounds.maxY
            let distance = maxY - visible.maxY
            let nearBottom = distance < 40
            if isFollowingLatest != nearBottom {
                isFollowingLatest = nearBottom
            }
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let labelKey: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(labelKey)
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
        }
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            Text("logs_loading")
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PMTheme.fieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PMTheme.fieldStroke, lineWidth: 1)
                )
        )
    }
}

private struct LogsThemePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            Text("common_loading")
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PMTheme.fieldBackground.opacity(0.6))
    }
}

#Preview {
    LogsView()
        .environmentObject(AppState())
}
