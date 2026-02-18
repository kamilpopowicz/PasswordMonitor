//
//  LogsView.swift
//  PasswordMonitor
//
//  Created by Kamil Popowicz on 09/02/2026.
//

import SwiftUI
import PasswordMonitorCore

struct LogsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var logStore = LogStore()
    @State private var searchText = ""
    @State private var selectedLevel: Logger.Level? = nil
    @State private var isAutoScrollEnabled = true
    @State private var autoScrollOverride: Bool? = nil
    @State private var showSearchField = false
    private let searchColumnWidth: CGFloat = 260
    private let searchButtonWidth: CGFloat = 28
    private let searchButtonSpacing: CGFloat = 6
    private let levelsColumnWidth: CGFloat = 430
    private let minWindowWidth: CGFloat = 730

    var body: some View {
        VStack(spacing: 0) {
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
                        LegendDot(color: .primary, labelKey: "logs_level_info")
                        LegendDot(color: .orange, labelKey: "logs_level_warning")
                        LegendDot(color: .red, labelKey: "logs_level_error")
                        LegendDot(color: PMTheme.textMuted, labelKey: "logs_level_debug")
                    }
                }
                .frame(width: levelsColumnWidth, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: searchButtonSpacing) {
                        SearchField(
                            text: $searchText,
                            placeholder: String(localized: "logs_search_placeholder"),
                            isDark: themeManager.isDarkAppearance
                        )
                            .frame(width: showSearchField ? (searchColumnWidth - searchButtonWidth - searchButtonSpacing) : 0)
                            .opacity(showSearchField ? 1 : 0)
                            .clipped()
                            .animation(.easeInOut(duration: 0.18), value: showSearchField)
                            .allowsHitTesting(showSearchField)

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showSearchField.toggle()
                                if !showSearchField { searchText = "" }
                            }
                        } label: {
                            Image(systemName: showSearchField ? "xmark" : "magnifyingglass")
                        }
                        .pmButton(role: .secondary, size: .compact)
                        .frame(width: searchButtonWidth)
                    }
                    .frame(width: searchColumnWidth, alignment: .trailing)

                    Text("logs_privacy_notice")
                        .font(.caption)
                        .foregroundColor(PMTheme.textSecondary)
                        .italic()
                        .multilineTextAlignment(.trailing)
                        .frame(width: searchColumnWidth, alignment: .trailing)
                }
            }
            .padding()

            Divider()

            ZStack {
                if themeManager.isApplyingTheme {
                    LogsThemePlaceholder()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if filteredContent.isEmpty {
                                    Text("logs_empty")
                                        .foregroundColor(PMTheme.textSecondary)
                                        .padding(.top, 8)
                                } else {
                                    let lines = filteredContent.split(separator: "\n", omittingEmptySubsequences: false)
                                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                        Text(String(line))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(color(for: String(line)))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                                    .background(GeometryReader { geo in
                                        Color.clear
                                            .preference(key: BottomOffsetKey.self, value: geo.frame(in: .named("logScroll")).maxY)
                                    })
                            }
                            .padding()
                        }
                        .coordinateSpace(name: "logScroll")
                        .onPreferenceChange(BottomOffsetKey.self) { value in
                            // Jeśli użytkownik jest blisko dołu, utrzymujemy auto-scroll
                            isAutoScrollEnabled = value < 60
                        }
                        .onChange(of: logStore.content) { _, _ in
                            let shouldScroll = autoScrollOverride ?? isAutoScrollEnabled
                            guard shouldScroll else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                        .onAppear {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                if logStore.isLoading {
                    LoadingOverlay()
                }
            }

            HStack {
                Toggle("logs_autoscroll", isOn: Binding(
                    get: { autoScrollOverride ?? isAutoScrollEnabled },
                    set: { autoScrollOverride = $0 }
                ))
                Button("logs_only_errors") {
                    selectedLevel = (selectedLevel == .error) ? nil : .error
                }
                .pmButton()
                Button("logs_copy_all") {
                    logStore.copyAll()
                }
                .pmButton()
                Button("logs_clear") {
                    logStore.clear()
                }
                .pmButton(role: .destructive)
                Spacer()
                Button("logs_reveal") {
                    logStore.revealInFinder()
                }
                .pmButton()
            }
            .padding([.horizontal, .top])

            Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
                .font(.caption2)
                .foregroundColor(PMTheme.textSecondary)
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
        .pmPanel()
        .padding()
        .frame(minWidth: minWindowWidth, minHeight: 420)
        .onAppear {
            logStore.start()
            appState.windowOpened()
        }
        .onDisappear {
            logStore.stop()
            appState.windowClosed()
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

    private func color(for line: String) -> Color {
        if line.contains("[ERROR]") { return .red }
        if line.contains("[WARN]") { return PMTheme.warning }
        if line.contains("[DEBUG]") { return PMTheme.textMuted }
        if line.contains("[INFO]") { return PMTheme.textPrimary }
        return PMTheme.textPrimary
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isDark: Bool

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
        applyAppearance(field)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        applyAppearance(nsView)
    }

    private func applyAppearance(_ field: NSSearchField) {
        if isDark {
            field.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.19, alpha: 0.95)
            field.textColor = NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.98, alpha: 1.0)
            field.appearance = NSAppearance(named: .darkAqua)
        } else {
            field.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 0.95)
            field.textColor = NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.26, alpha: 1.0)
            field.appearance = NSAppearance(named: .aqua)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}

private struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
