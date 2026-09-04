import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ble: BLEManager
    @State private var showingSettings = false

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
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BLEManager())
}
