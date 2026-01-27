struct SettingsView: View {
    @State private var launchAtLogin = false
    
    var body: some View {
        Form {
            Toggle("Uruchom przy logowaniu", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    let service = SMAppService.mainApp
                    do {
                        if newValue {
                            try service.register()
                        } else {
                            try service.unregister()
                        }
                    } catch {
                        print("Error: \(error)")
                    }
                }
        }
        .padding()
        .frame(width: 400, height: 200)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
