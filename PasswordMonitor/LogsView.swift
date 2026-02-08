import SwiftUI
import PasswordMonitorCore

struct LogsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var logStore = LogStore()
    @State private var searchText = ""
    @State private var selectedLevel: Logger.Level? = nil
    @State private var isAutoScrollEnabled = true
    @State private var autoScrollOverride: Bool? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("logs_title")
                    .font(.headline)
                Spacer()
                Picker("logs_level_filter", selection: $selectedLevel) {
                    Text("logs_level_all").tag(Logger.Level?.none)
                    Text("logs_level_debug").tag(Logger.Level?.some(.debug))
                    Text("logs_level_info").tag(Logger.Level?.some(.info))
                    Text("logs_level_warning").tag(Logger.Level?.some(.warning))
                    Text("logs_level_error").tag(Logger.Level?.some(.error))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                HStack(spacing: 8) {
                    Text("logs_legend")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    LegendDot(color: .red, labelKey: "logs_level_error")
                    LegendDot(color: .orange, labelKey: "logs_level_warning")
                    LegendDot(color: .secondary, labelKey: "logs_level_debug")
                    LegendDot(color: .primary, labelKey: "logs_level_info")
                }
            }
            .padding()

            HStack {
                TextField("logs_search_placeholder", text: $searchText)
                    .textFieldStyle(.roundedBorder)
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
                Button("logs_export") {
                    logStore.exportLog(content: filteredContent)
                }
                Button("logs_reveal") {
                    logStore.revealInFinder()
                }
                Button("logs_clear") {
                    logStore.clear()
                }
            }
            .padding([.horizontal, .bottom])

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
        }
        .frame(minWidth: 640, minHeight: 400)
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
