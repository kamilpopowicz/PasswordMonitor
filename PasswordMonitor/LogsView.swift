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
                            .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
                        LegendDot(color: .primary, labelKey: "logs_level_info")
                        LegendDot(color: .orange, labelKey: "logs_level_warning")
                        LegendDot(color: .red, labelKey: "logs_level_error")
                        LegendDot(color: .secondary, labelKey: "logs_level_debug")
                    }
                }
                .frame(width: levelsColumnWidth, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: searchButtonSpacing) {
                        SearchField(text: $searchText, placeholder: String(localized: "logs_search_placeholder"))
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
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(width: searchButtonWidth)
                    }
                    .frame(width: searchColumnWidth, alignment: .trailing)

                    Text("logs_privacy_notice")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .multilineTextAlignment(.trailing)
                        .frame(width: searchColumnWidth, alignment: .trailing)
                }
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if filteredContent.isEmpty {
                            Text("logs_empty")
                                .foregroundColor(.secondary)
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

            HStack {
                Toggle("logs_autoscroll", isOn: Binding(
                    get: { autoScrollOverride ?? isAutoScrollEnabled },
                    set: { autoScrollOverride = $0 }
                ))
                Button("logs_only_errors") {
                    selectedLevel = (selectedLevel == .error) ? nil : .error
                }
                Button("logs_copy_all") {
                    logStore.copyAll()
                }
                Button("logs_clear") {
                    logStore.clear()
                }
                Spacer()
                Button("logs_reveal") {
                    logStore.revealInFinder()
                }
            }
            .padding([.horizontal, .top])

            Text("Copyright (c) 2026 Kamil Popowicz. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .frame(minWidth: minWindowWidth, minHeight: 400)
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
        if line.contains("[WARN]") { return .orange }
        if line.contains("[DEBUG]") { return .secondary }
        if line.contains("[INFO]") { return .primary }
        return .primary
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = true
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
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
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    LogsView()
        .environmentObject(AppState())
}
