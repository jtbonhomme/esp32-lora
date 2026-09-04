import SwiftUI

struct ScanListView: View {
    @EnvironmentObject private var ble: BLEManager

    var body: some View {
        VStack(spacing: 16) {
            statusHeader

            if case .bluetoothUnavailable = ble.state {
                Spacer()
            } else if ble.discoveredDevices.isEmpty {
                Spacer()
                ProgressView()
                Text("Looking for \u{201C}\(ble.targetName)\u{201D}\u{2026}")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            } else {
                List(ble.discoveredDevices) { device in
                    Button {
                        ble.connect(to: device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(.headline)
                                Text("RSSI \(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Connect")
                                .font(.subheadline.bold())
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.top)
        .navigationTitle("ESP32 Chat")
        .onAppear { ble.startScanning() }
    }

    @ViewBuilder
    private var statusHeader: some View {
        switch ble.state {
        case .bluetoothUnavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.horizontal)
        case .connecting(let name):
            Label("Connecting to \(name)\u{2026}", systemImage: "antenna.radiowaves.left.and.right")
                .padding(.horizontal)
        case .disconnected:
            Label("Disconnected \u{2014} rescanning", systemImage: "wifi.slash")
                .foregroundStyle(.orange)
                .padding(.horizontal)
        default:
            EmptyView()
        }
    }
}

#Preview {
    NavigationStack {
        ScanListView()
            .environmentObject(BLEManager())
    }
}
