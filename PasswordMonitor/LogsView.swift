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

    var body: some View {
        VStack(spacing: PMLayout.noSpacing) {
            PMWindowContentContainer {
                controlsCard
                    .pmContentCard()
            }
            .padding(.top, PMLayout.contentPadding)
            .padding(.bottom, PMLayout.sectionSpacing)

            PMWindowContentContainer {
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
                        .pmFieldPanel(strokeOpacity: PMTheme.fieldSoftStrokeOpacity)
                    }

                    if logStore.isLoading {
                        LoadingOverlay()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .pmContentCard(padding: PMLayout.contentCardCompactPadding)
            }
            .padding(.bottom, PMLayout.sectionSpacing)
            .layoutPriority(1)

            PMWindowFooterHost()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            logStore.start()
            logStore.reload()
            appState.windowOpened()
            isFollowingLatest = true
            scrollToBottomToken = UUID()
            DispatchQueue.main.async {
                appState.activateApp()
                refreshWindowTitle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            refreshWindowTitle()
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

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: PMLayout.controlSpacing) {
            PMAdaptiveActionRow(spacing: PMLayout.compactSpacing) {
                logActionButton(LanguageSettings.localizedString("logs_now"), role: isFollowingLatest ? .primary : .secondary) {
                    isFollowingLatest = true
                    logStore.reload()
                    scrollToBottomToken = UUID()
                }

                logActionButton(LanguageSettings.localizedString("logs_clear"), role: .destructive) {
                    logStore.clear()
                }

                logActionButton(LanguageSettings.localizedString("logs_reload")) {
                    logStore.reload()
                }

                logActionButton(LanguageSettings.localizedString("logs_reveal")) {
                    logStore.revealInFinder()
                }

                logActionButton(LanguageSettings.localizedString("logs_export")) {
                    logStore.share()
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: PMLayout.compactSpacing) {
                    logsLevelLabel
                        .frame(width: PMLayout.logsFilterLabelWidth, alignment: .leading)
                    levelPicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
                    logsLevelLabel
                    levelPicker
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: PMLayout.compactSpacing) {
                    logsRefreshLabel
                        .frame(width: PMLayout.logsFilterLabelWidth, alignment: .leading)
                    refreshPicker
                        .frame(width: PMLayout.logsRefreshPickerWidth, alignment: .leading)

                    Spacer(minLength: PMLayout.zeroMinLength)

                    logsSearchControls
                }

                VStack(alignment: .leading, spacing: PMLayout.compactSpacing) {
                    logsRefreshLabel
                    refreshPicker
                    logsSearchControls
                }
            }

            Text(LanguageSettings.localizedString("logs_privacy_notice"))
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
                .italic()
                .pmMultilineText()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logsLevelLabel: some View {
        (Text(LanguageSettings.localizedString("logs_level_filter")) + Text(":"))
            .font(.caption)
            .foregroundColor(PMTheme.textSecondary)
    }

    private var levelPicker: some View {
        Picker("", selection: $selectedLevel) {
            Text(LanguageSettings.localizedString("logs_level_all")).tag(Logger.Level?.none)
            Text(LanguageSettings.localizedString("logs_level_info")).tag(Logger.Level?.some(.info))
            Text(LanguageSettings.localizedString("logs_level_warning")).tag(Logger.Level?.some(.warning))
            Text(LanguageSettings.localizedString("logs_level_error")).tag(Logger.Level?.some(.error))
            Text(LanguageSettings.localizedString("logs_level_debug")).tag(Logger.Level?.some(.debug))
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var logsRefreshLabel: some View {
        (Text(LanguageSettings.localizedString("logs_refresh_label")) + Text(":"))
            .font(.caption)
            .foregroundColor(PMTheme.textSecondary)
    }

    private var refreshPicker: some View {
        Picker("", selection: $logStore.refreshMode) {
            Text(LanguageSettings.localizedString("logs_refresh_immediate")).tag(LogStore.RefreshMode.immediate)
            Text(LanguageSettings.localizedString("logs_refresh_1m")).tag(LogStore.RefreshMode.oneMinute)
            Text(LanguageSettings.localizedString("logs_refresh_5m")).tag(LogStore.RefreshMode.fiveMinutes)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var logsSearchControls: some View {
        HStack(spacing: PMLayout.logsSearchButtonSpacing) {
            SearchField(
                text: $searchText,
                placeholder: LanguageSettings.localizedString("logs_search_placeholder"),
                isDark: themeManager.isDarkAppearance,
                isVisible: showSearchField,
                focusToken: $searchFocusToken
            )
            .frame(width: showSearchField ? PMLayout.logsCompactSearchFieldWidth : PMLayout.noSpacing)
            .opacity(showSearchField ? PMControlMetrics.visibleOpacity : PMControlMetrics.hiddenOpacity)
            .clipped()
            .animation(.easeInOut(duration: PMMotion.quickAnimationDuration), value: showSearchField)
            .allowsHitTesting(showSearchField)

            Button {
                withAnimation(.easeInOut(duration: PMMotion.quickAnimationDuration)) {
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
            .help(showSearchField ? LanguageSettings.localizedString("logs_search_close") : LanguageSettings.localizedString("logs_search"))
        }
        .frame(width: showSearchField ? PMLayout.logsCompactSearchColumnWidth : PMLayout.logsSearchButtonWidth, alignment: .trailing)
    }

    private func logActionButton(
        _ title: String,
        role: PMButtonRole = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .pmMultilineText(alignment: .center)
                .minimumScaleFactor(PMLayout.menuButtonMinimumScale)
                .frame(maxWidth: .infinity)
        }
        .pmButton(role: role, size: .compact)
        .frame(maxWidth: .infinity)
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
                string: LanguageSettings.localizedString("logs_empty"),
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

    private func refreshWindowTitle() {
        let title = LanguageSettings.localizedString("logs_window_title")
        if let keyWindow = NSApp.keyWindow {
            keyWindow.title = title
            return
        }
        if let logsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "logs-window" }) {
            logsWindow.title = title
        }
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
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: PMLayout.logTextInsetWidth, height: PMLayout.logTextInsetHeight)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = isDark ? NSColor(PMTheme.textPrimary) : NSColor(PMTheme.textPrimary)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        configureTextLayout(textView, in: scrollView)
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
        textView.backgroundColor = .clear
        configureTextLayout(textView, in: nsView)

        if textView.textStorage?.length != attributedText.length ||
            textView.attributedString() != attributedText {
            textView.textStorage?.setAttributedString(attributedText)
        }

        if context.coordinator.lastScrollToken != scrollToBottomToken {
            context.coordinator.lastScrollToken = scrollToBottomToken
            scrollToBottom(nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSView.boundsDidChangeNotification,
            object: nsView.contentView
        )
    }

    private func configureTextLayout(_ textView: NSTextView, in scrollView: NSScrollView) {
        let contentSize = scrollView.contentSize
        textView.minSize = NSSize(width: PMLayout.noSpacing, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.frame.size.width = contentSize.width
    }

    private func scrollToBottom(_ scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let length = (textView.string as NSString).length
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
            let nearBottom = distance < PMLayout.logFollowThreshold
            if isFollowingLatest != nearBottom {
                isFollowingLatest = nearBottom
            }
        }
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        VStack(spacing: PMLayout.compactSpacing) {
            ProgressView()
                .controlSize(.large)
            Text(LanguageSettings.localizedString("logs_loading"))
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
        }
        .pmFieldPanel(padding: PMLayout.contentCardPadding)
    }
}

private struct LogsThemePlaceholder: View {
    var body: some View {
        VStack(spacing: PMLayout.compactSpacing) {
            ProgressView()
                .controlSize(.large)
            Text(LanguageSettings.localizedString("common_loading"))
                .font(.caption)
                .foregroundColor(PMTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PMTheme.fieldBackground.opacity(PMTheme.fieldPlaceholderFillOpacity))
    }
}
