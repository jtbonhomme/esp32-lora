import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ble: BLEManager
    @State private var showingSettings = false
    @State private var showingDebugLog = false

    var body: some View {
        NavigationStack {
            Group {
                if case .connected = ble.state {
                    ChatView()
                } else {
                    ScanListView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingDebugLog = true
                    } label: {
                        Image(systemName: "ladybug")
                    }
                    .accessibilityLabel("Debug Log")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingDebugLog) {
                DebugLogView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BLEManager())
}
