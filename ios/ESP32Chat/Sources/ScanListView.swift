import SwiftUI

struct ScanListView: View {
    @EnvironmentObject private var ble: BLEManager

    private var matchingDevices: [DiscoveredDevice] {
        ble.discoveredDevices.filter(\.isTargetMatch)
    }

    private var otherDevices: [DiscoveredDevice] {
        ble.discoveredDevices.filter { !$0.isTargetMatch }
    }

    var body: some View {
        VStack(spacing: 16) {
            statusHeader

            if let lastError = ble.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(.horizontal)
                    .multilineTextAlignment(.leading)
            }

            if case .bluetoothUnavailable = ble.state {
                Spacer()
            } else if ble.discoveredDevices.isEmpty {
                Spacer()
                ProgressView()
                Text("Looking for \u{201C}\(ble.targetName)\u{201D}\u{2026}")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("No BLE devices advertising the ESP32 Chat service seen yet. Make sure the board is flashed with sketches/ble (check its serial monitor for an \u{201C}advertising as\u{2026}\u{201D} line).")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            } else {
                List {
                    if !matchingDevices.isEmpty {
                        Section("Matches \u{201C}\(ble.targetName)\u{201D}") {
                            ForEach(matchingDevices) { device in
                                deviceRow(device)
                            }
                        }
                    }
                    if !otherDevices.isEmpty {
                        Section {
                            ForEach(otherDevices) { device in
                                deviceRow(device)
                            }
                        } header: {
                            Text("Other ESP32 Chat devices nearby")
                        } footer: {
                            Text("These run the same firmware but advertise a different name than \u{201C}\(ble.targetName)\u{201D}. Connect anyway, or update the name in Settings to match.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .padding(.top)
        .navigationTitle("ESP32 Chat")
        .onAppear { ble.startScanning() }
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
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
