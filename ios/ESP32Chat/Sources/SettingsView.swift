import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dismiss) private var dismiss
    @State private var targetNameDraft = ""
    @State private var senderNameDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Device name", text: $targetNameDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("ESP32 BLE name")
                } footer: {
                    Text("Must match the BLE_NAME the firmware was built with (default \u{201C}Heltec-BLE\u{201D}).")
                }

                Section {
                    TextField("Your name", text: $senderNameDraft)
                        .autocorrectionDisabled()
                } header: {
                    Text("Sender name")
                } footer: {
                    Text("Shown on the ESP32's OLED screen next to each message you send.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: applyAndDismiss)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                targetNameDraft = ble.targetName
                senderNameDraft = ble.senderName
            }
        }
    }

    private func applyAndDismiss() {
        let trimmedTarget = targetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSender = senderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTarget.isEmpty, trimmedTarget != ble.targetName {
            ble.targetName = trimmedTarget
            ble.startScanning()
        }
        if !trimmedSender.isEmpty {
            ble.senderName = trimmedSender
        }
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(BLEManager())
}
