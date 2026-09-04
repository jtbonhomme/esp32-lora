import Foundation
import CoreBluetooth
import UIKit

struct ChatMessage: Identifiable, Equatable {
    enum Direction { case sent, received }

    let id = UUID()
    let direction: Direction
    let sender: String
    let text: String
    let date = Date()
}

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
    var isTargetMatch: Bool

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

enum ConnectionState: Equatable {
    case idle
    case scanning
    case connecting(String)
    case connected(String)
    case disconnected
    case bluetoothUnavailable(String)
}

/// Talks to the sketches/ble firmware over a Nordic UART-style BLE service.
/// Scanning is filtered to peripherals advertising `serviceUUID` (so only
/// boards running that firmware ever show up); `targetName` is then used to
/// highlight/pre-select the expected device without hiding others, since a
/// board's actual BLE_NAME can drift out of sync with this app's setting.
final class BLEManager: NSObject, ObservableObject {
    // Must match the UUIDs in sketches/ble/ble.ino.
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // central -> peripheral
    static let txCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // peripheral -> central

    // CoreBluetooth's connect(_:options:) has NO built-in timeout: if the
    // peripheral never responds at the link layer, neither didConnect nor
    // didFailToConnect ever fires and the UI would hang on "Connecting..."
    // forever with no error. We enforce our own timeout and cancel + report.
    private static let connectTimeout: TimeInterval = 12
    private static let maxLogLines = 300

    private static let targetNameDefaultsKey = "targetName"
    private static let senderNameDefaultsKey = "senderName"
    private static let defaultTargetName = "Heltec-BLE"

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    @Published var targetName: String {
        didSet { UserDefaults.standard.set(targetName, forKey: Self.targetNameDefaultsKey) }
    }
    @Published var senderName: String {
        didSet { UserDefaults.standard.set(senderName, forKey: Self.senderNameDefaultsKey) }
    }
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var lastError: String?
    @Published private(set) var debugLog: [String] = []

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var pendingPeripheral: CBPeripheral?
    private var connectTimeoutWorkItem: DispatchWorkItem?

    override init() {
        let defaults = UserDefaults.standard
        targetName = defaults.string(forKey: Self.targetNameDefaultsKey) ?? Self.defaultTargetName
        senderName = defaults.string(forKey: Self.senderNameDefaultsKey) ?? UIDevice.current.name
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        discoveredDevices.removeAll()
        guard central.state == .poweredOn else { return }
        state = .scanning
        log("Scanning for service \(Self.serviceUUID.uuidString)\u{2026}")
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        if case .scanning = state { state = .idle }
    }

    func connect(to device: DiscoveredDevice) {
        stopScanning()
        cancelConnectTimeout()
        lastError = nil
        pendingPeripheral = device.peripheral
        state = .connecting(device.name)
        log("Connecting to \(device.name) [\(device.id.uuidString)]\u{2026}")
        central.connect(device.peripheral, options: nil)
        scheduleConnectTimeout(for: device.peripheral, name: device.name)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        log("Disconnecting from \(peripheral.name ?? targetName) by user request")
        central.cancelPeripheralConnection(peripheral)
    }

    func clearDebugLog() {
        debugLog.removeAll()
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let peripheral = connectedPeripheral, let rx = rxCharacteristic else {
            log("Send failed: not connected or RX characteristic not ready")
            return
        }
        guard let data = "\(senderName)|\(trimmed)".data(using: .utf8) else { return }

        let writeType: CBCharacteristicWriteType = rx.properties.contains(.write) ? .withResponse : .withoutResponse
        log("Writing \(data.count) bytes to RX (\(writeType == .withResponse ? "with response" : "without response"))")
        peripheral.writeValue(data, for: rx, type: writeType)
        messages.append(ChatMessage(direction: .sent, sender: senderName, text: trimmed))
    }

    // MARK: - Debug log

    private func log(_ message: String) {
        let line = "[\(Self.logTimeFormatter.string(from: Date()))] \(message)"
        debugLog.append(line)
        if debugLog.count > Self.maxLogLines {
            debugLog.removeFirst(debugLog.count - Self.maxLogLines)
        }
        #if DEBUG
        print(line)
        #endif
    }

    private func describe(_ error: Error?) -> String? {
        guard let error else { return nil }
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))"
    }

    // MARK: - Connect timeout

    private func scheduleConnectTimeout(for peripheral: CBPeripheral, name: String) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.pendingPeripheral?.identifier == peripheral.identifier else { return }
            let message = "Connection to \(name) timed out after \(Int(Self.connectTimeout))s (no response from the board)"
            self.log(message)
            self.lastError = message
            self.pendingPeripheral = nil
            self.central.cancelPeripheralConnection(peripheral)
            self.state = .disconnected
            self.startScanning()
        }
        connectTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout, execute: workItem)
    }

    private func cancelConnectTimeout() {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
    }
}

private func describeManagerState(_ state: CBManagerState) -> String {
    switch state {
    case .unknown: return "unknown"
    case .resetting: return "resetting"
    case .unsupported: return "unsupported"
    case .unauthorized: return "unauthorized"
    case .poweredOff: return "poweredOff"
    case .poweredOn: return "poweredOn"
    @unknown default: return "unknown(\(state.rawValue))"
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("Central state: \(describeManagerState(central.state))")
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff:
            state = .bluetoothUnavailable("Bluetooth is turned off")
        case .unauthorized:
            state = .bluetoothUnavailable("Bluetooth access not authorized")
        case .unsupported:
            state = .bluetoothUnavailable("Bluetooth is not supported on this device")
        default:
            state = .idle
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // The scan above is already filtered to peripherals advertising our
        // GATT service UUID, so anything reaching this callback is running
        // sketches/ble firmware. We don't filter out a name mismatch here —
        // instead we surface it in the UI (see ScanListView) so a BLE_NAME
        // that doesn't match the app's configured target name is visible
        // and connectable, rather than silently dropped.
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "(unnamed)"
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? true

        let device = DiscoveredDevice(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: advertisedName,
            rssi: RSSI.intValue,
            isTargetMatch: advertisedName == targetName
        )
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index].rssi = device.rssi
            discoveredDevices[index].isTargetMatch = device.isTargetMatch
        } else {
            log("Discovered \u{201C}\(advertisedName)\u{201D} [\(peripheral.identifier.uuidString)] rssi=\(RSSI.intValue) connectable=\(isConnectable)")
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        cancelConnectTimeout()
        pendingPeripheral = nil
        log("Link-layer connected to \(peripheral.name ?? "?") [\(peripheral.identifier.uuidString)], discovering services\u{2026}")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cancelConnectTimeout()
        pendingPeripheral = nil
        let message = describe(error) ?? "Connection failed (no error details from CoreBluetooth)"
        log("Failed to connect to \(peripheral.name ?? "?"): \(message)")
        lastError = message
        state = .disconnected
        connectedPeripheral = nil
        rxCharacteristic = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cancelConnectTimeout()
        pendingPeripheral = nil
        if let message = describe(error) {
            log("Disconnected from \(peripheral.name ?? "?"): \(message)")
            lastError = message
        } else {
            log("Disconnected from \(peripheral.name ?? "?")")
        }
        state = .disconnected
        connectedPeripheral = nil
        rxCharacteristic = nil
        startScanning()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let message = describe(error) {
            log("Service discovery failed: \(message)")
            lastError = message
            return
        }
        guard let services = peripheral.services else {
            log("Service discovery returned no services")
            return
        }
        log("Discovered \(services.count) service(s): \(services.map(\.uuid.uuidString).joined(separator: ", "))")
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.rxCharacteristicUUID, Self.txCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let message = describe(error) {
            log("Characteristic discovery failed for service \(service.uuid.uuidString): \(message)")
            lastError = message
            return
        }
        guard let characteristics = service.characteristics else {
            log("Characteristic discovery returned nothing for service \(service.uuid.uuidString)")
            return
        }
        log("Discovered \(characteristics.count) characteristic(s) for \(service.uuid.uuidString)")
        for characteristic in characteristics {
            switch characteristic.uuid {
            case Self.rxCharacteristicUUID:
                rxCharacteristic = characteristic
                log("RX characteristic ready (properties: \(characteristic.properties.rawValue))")
            case Self.txCharacteristicUUID:
                log("Subscribing to TX notifications\u{2026}")
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                log("Ignoring unexpected characteristic \(characteristic.uuid.uuidString)")
            }
        }
        state = .connected(peripheral.name ?? targetName)
        log("Ready to chat with \(peripheral.name ?? targetName)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let message = describe(error) {
            log("Failed to subscribe to \(characteristic.uuid.uuidString): \(message)")
            lastError = message
        } else {
            log("Subscription state for \(characteristic.uuid.uuidString): notifying=\(characteristic.isNotifying)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let message = describe(error) {
            log("Write to \(characteristic.uuid.uuidString) failed: \(message)")
            lastError = message
        } else {
            log("Write to \(characteristic.uuid.uuidString) acknowledged")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let message = describe(error) {
            log("Value update failed for \(characteristic.uuid.uuidString): \(message)")
            lastError = message
            return
        }
        guard characteristic.uuid == Self.txCharacteristicUUID,
              let data = characteristic.value,
              let text = String(data: data, encoding: .utf8) else { return }
        log("Received \(data.count) bytes on TX: \(text)")
        messages.append(ChatMessage(direction: .received, sender: targetName, text: text))
    }
}
