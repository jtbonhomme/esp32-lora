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

/// Talks to the sketches/ble firmware over a Nordic UART-style BLE service:
/// scans for a peripheral advertising a specific name, connects, and
/// exchanges "<sender>|<message>" text payloads.
final class BLEManager: NSObject, ObservableObject {
    // Must match the UUIDs in sketches/ble/ble.ino.
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // central -> peripheral
    static let txCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // peripheral -> central

    private static let targetNameDefaultsKey = "targetName"
    private static let senderNameDefaultsKey = "senderName"
    private static let defaultTargetName = "Heltec-BLE"

    @Published var targetName: String {
        didSet { UserDefaults.standard.set(targetName, forKey: Self.targetNameDefaultsKey) }
    }
    @Published var senderName: String {
        didSet { UserDefaults.standard.set(senderName, forKey: Self.senderNameDefaultsKey) }
    }
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var messages: [ChatMessage] = []

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?

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
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        if case .scanning = state { state = .idle }
    }

    func connect(to device: DiscoveredDevice) {
        stopScanning()
        state = .connecting(device.name)
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let peripheral = connectedPeripheral,
              let rx = rxCharacteristic,
              let data = "\(senderName)|\(trimmed)".data(using: .utf8) else { return }

        let writeType: CBCharacteristicWriteType = rx.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: rx, type: writeType)
        messages.append(ChatMessage(direction: .sent, sender: senderName, text: trimmed))
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
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
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard advertisedName == targetName else { return }

        let device = DiscoveredDevice(id: peripheral.identifier, peripheral: peripheral, name: advertisedName, rssi: RSSI.intValue)
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index].rssi = device.rssi
        } else {
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        connectedPeripheral = nil
        rxCharacteristic = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        connectedPeripheral = nil
        rxCharacteristic = nil
        startScanning()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.rxCharacteristicUUID, Self.txCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case Self.rxCharacteristicUUID:
                rxCharacteristic = characteristic
            case Self.txCharacteristicUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        state = .connected(peripheral.name ?? targetName)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.txCharacteristicUUID,
              let data = characteristic.value,
              let text = String(data: data, encoding: .utf8) else { return }
        messages.append(ChatMessage(direction: .received, sender: targetName, text: text))
    }
}
