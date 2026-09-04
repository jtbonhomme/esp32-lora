package com.jtbonhomme.esp32chat.ble

import android.annotation.SuppressLint
import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.ParcelUuid
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * Talks to the sketches/ble firmware over a Nordic UART-style BLE service.
 * Mirrors ios/ESP32Chat/Sources/BLEManager.swift: scanning is filtered to
 * [SERVICE_UUID] (so only boards running that firmware ever show up),
 * `targetName` highlights/pre-selects the expected device without hiding
 * others, connect() enforces its own timeout (Android's BluetoothGatt has
 * no built-in one either), and every callback logs to [debugLog] with
 * GATT status details on failure.
 */
class BleViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        // Must match the UUIDs in sketches/ble/ble.ino.
        val SERVICE_UUID: UUID = UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        val RX_CHARACTERISTIC_UUID: UUID = UUID.fromString("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        val TX_CHARACTERISTIC_UUID: UUID = UUID.fromString("6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        // BluetoothGatt.connect() has no built-in timeout either: a
        // non-responding peripheral would otherwise hang on "Connecting..."
        // forever with no callback at all.
        private const val CONNECT_TIMEOUT_MS = 12_000L
        private const val MAX_LOG_LINES = 300

        private const val PREFS_NAME = "esp32chat_prefs"
        private const val KEY_TARGET_NAME = "targetName"
        private const val KEY_SENDER_NAME = "senderName"
        private const val DEFAULT_TARGET_NAME = "Heltec-BLE"
    }

    private val prefs: SharedPreferences =
        application.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val bluetoothManager =
        application.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager.adapter
    private var scanner: BluetoothLeScanner? = null
    private var gatt: BluetoothGatt? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private var pendingDeviceAddress: String? = null
    private var connectTimeoutJob: Job? = null

    private val logTimeFormat = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    private val _targetName =
        MutableStateFlow(prefs.getString(KEY_TARGET_NAME, DEFAULT_TARGET_NAME) ?: DEFAULT_TARGET_NAME)
    val targetName: StateFlow<String> = _targetName.asStateFlow()

    private val _senderName =
        MutableStateFlow(prefs.getString(KEY_SENDER_NAME, Build.MODEL) ?: Build.MODEL)
    val senderName: StateFlow<String> = _senderName.asStateFlow()

    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Idle)
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _discoveredDevices = MutableStateFlow<List<DiscoveredDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<DiscoveredDevice>> = _discoveredDevices.asStateFlow()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private val _debugLog = MutableStateFlow<List<String>>(emptyList())
    val debugLog: StateFlow<List<String>> = _debugLog.asStateFlow()

    fun setTargetName(name: String) {
        _targetName.value = name
        prefs.edit().putString(KEY_TARGET_NAME, name).apply()
    }

    fun setSenderName(name: String) {
        _senderName.value = name
        prefs.edit().putString(KEY_SENDER_NAME, name).apply()
    }

    fun clearDebugLog() {
        _debugLog.value = emptyList()
    }

    private fun log(message: String) {
        val line = "[${logTimeFormat.format(Date())}] $message"
        val updated = _debugLog.value + line
        _debugLog.value = if (updated.size > MAX_LOG_LINES) {
            updated.subList(updated.size - MAX_LOG_LINES, updated.size)
        } else {
            updated
        }
    }

    /** Call once Bluetooth permissions are confirmed granted. */
    @SuppressLint("MissingPermission")
    fun startScanning() {
        val bleAdapter = adapter
        if (bleAdapter == null) {
            _state.value = ConnectionState.BluetoothUnavailable("Bluetooth is not supported on this device")
            return
        }
        if (!bleAdapter.isEnabled) {
            _state.value = ConnectionState.BluetoothUnavailable("Bluetooth is turned off")
            return
        }
        val bleScanner = bleAdapter.bluetoothLeScanner
        if (bleScanner == null) {
            _state.value = ConnectionState.BluetoothUnavailable("Bluetooth LE scanner unavailable")
            return
        }
        scanner = bleScanner
        _discoveredDevices.value = emptyList()
        _state.value = ConnectionState.Scanning
        log("Scanning for service $SERVICE_UUID…")
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        try {
            bleScanner.startScan(listOf(filter), settings, scanCallback)
        } catch (e: SecurityException) {
            log("Scan failed: ${e.message}")
            _lastError.value = "Missing Bluetooth permission: ${e.message}"
        }
    }

    @SuppressLint("MissingPermission")
    fun stopScanning() {
        try {
            scanner?.stopScan(scanCallback)
        } catch (_: SecurityException) {
            // Permission already revoked while stopping — nothing to do.
        }
        if (_state.value is ConnectionState.Scanning) {
            _state.value = ConnectionState.Idle
        }
    }

    @SuppressLint("MissingPermission")
    fun connect(device: DiscoveredDevice) {
        stopScanning()
        cancelConnectTimeout()
        _lastError.value = null
        pendingDeviceAddress = device.id
        _state.value = ConnectionState.Connecting(device.name)
        log("Connecting to ${device.name} [${device.id}]…")
        gatt = device.device.connectGatt(getApplication(), false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        scheduleConnectTimeout(device.id, device.name)
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        log("Disconnecting by user request")
        gatt?.disconnect()
    }

    @SuppressLint("MissingPermission")
    fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val activeGatt = gatt
        val rx = rxCharacteristic
        if (activeGatt == null || rx == null) {
            log("Send failed: not connected or RX characteristic not ready")
            return
        }
        val payload = "${_senderName.value}|$trimmed".toByteArray(Charsets.UTF_8)
        val writeType = if (rx.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        val kind = if (writeType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) "with response" else "without response"
        log("Writing ${payload.size} bytes to RX ($kind)")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activeGatt.writeCharacteristic(rx, payload, writeType)
        } else {
            @Suppress("DEPRECATION")
            rx.writeType = writeType
            @Suppress("DEPRECATION")
            rx.value = payload
            @Suppress("DEPRECATION")
            activeGatt.writeCharacteristic(rx)
        }
        _messages.value = _messages.value +
            ChatMessage(direction = ChatMessage.Direction.SENT, sender = _senderName.value, text = trimmed)
    }

    private fun scheduleConnectTimeout(address: String, name: String) {
        connectTimeoutJob = viewModelScope.launch {
            delay(CONNECT_TIMEOUT_MS)
            if (pendingDeviceAddress != address) return@launch
            val message = "Connection to $name timed out after ${CONNECT_TIMEOUT_MS / 1000}s (no response from the board)"
            log(message)
            _lastError.value = message
            pendingDeviceAddress = null
            closeGatt()
            _state.value = ConnectionState.Disconnected
            startScanning()
        }
    }

    private fun cancelConnectTimeout() {
        connectTimeoutJob?.cancel()
        connectTimeoutJob = null
    }

    @SuppressLint("MissingPermission")
    private fun closeGatt() {
        gatt?.close()
        gatt = null
        rxCharacteristic = null
    }

    /** Known android.bluetooth GATT status codes (few are documented as
     *  named constants), with a short actionable hint for the common ones. */
    private fun gattStatusDescription(status: Int): String {
        val name = when (status) {
            BluetoothGatt.GATT_SUCCESS -> "GATT_SUCCESS"
            8 -> "GATT_CONN_TIMEOUT"
            19 -> "GATT_CONN_TERMINATE_PEER_USER"
            22 -> "GATT_CONN_TERMINATE_LOCAL_HOST"
            34 -> "GATT_CONN_LMP_TIMEOUT"
            62 -> "GATT_CONN_FAIL_ESTABLISH"
            133 -> "GATT_ERROR (generic Android BLE stack failure)"
            else -> "status $status"
        }
        val hint = when (status) {
            133 -> " — often transient on Android; the app will retry the scan. If it persists, forget/unpair the device in Android Bluetooth settings."
            8, 62 -> " — the board didn't respond in time; check it's powered on and in range."
            19 -> " — the board closed the connection."
            else -> ""
        }
        return "$name$hint"
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val advertisedName = result.scanRecord?.deviceName ?: device.name ?: "(unnamed)"
            val match = advertisedName == _targetName.value

            val existing = _discoveredDevices.value
            val index = existing.indexOfFirst { it.id == device.address }
            val updated = DiscoveredDevice(
                id = device.address,
                device = device,
                name = advertisedName,
                rssi = result.rssi,
                isTargetMatch = match
            )
            _discoveredDevices.value = if (index >= 0) {
                existing.toMutableList().also { it[index] = updated }
            } else {
                log("Discovered \"$advertisedName\" [${device.address}] rssi=${result.rssi}")
                existing + updated
            }
        }

        override fun onScanFailed(errorCode: Int) {
            log("Scan failed: error code $errorCode")
            _lastError.value = "Scan failed (error code $errorCode)"
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    cancelConnectTimeout()
                    pendingDeviceAddress = null
                    log("Link-layer connected to ${g.device.address}, discovering services…")
                    g.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    cancelConnectTimeout()
                    pendingDeviceAddress = null
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        val message = gattStatusDescription(status)
                        log("Disconnected (status=$status): $message")
                        _lastError.value = message
                    } else {
                        log("Disconnected from ${g.device.address}")
                    }
                    closeGatt()
                    _state.value = ConnectionState.Disconnected
                    startScanning()
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                val message = gattStatusDescription(status)
                log("Service discovery failed: $message")
                _lastError.value = message
                return
            }
            val services = g.services
            log("Discovered ${services.size} service(s): ${services.joinToString(", ") { it.uuid.toString() }}")

            val service = g.getService(SERVICE_UUID)
            if (service == null) {
                log("Target service $SERVICE_UUID not found on this peripheral")
                return
            }

            val rx = service.getCharacteristic(RX_CHARACTERISTIC_UUID)
            val tx = service.getCharacteristic(TX_CHARACTERISTIC_UUID)
            rxCharacteristic = rx
            if (rx != null) {
                log("RX characteristic ready (properties: ${rx.properties})")
            } else {
                log("RX characteristic not found")
            }
            if (tx != null) {
                log("Subscribing to TX notifications…")
                g.setCharacteristicNotification(tx, true)
                val cccd = tx.getDescriptor(CCCD_UUID)
                if (cccd != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    } else {
                        @Suppress("DEPRECATION")
                        cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        @Suppress("DEPRECATION")
                        g.writeDescriptor(cccd)
                    }
                }
            } else {
                log("TX characteristic not found")
            }

            _state.value = ConnectionState.Connected(g.device.name ?: _targetName.value)
            log("Ready to chat with ${g.device.name ?: _targetName.value}")
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                log("Subscribed to ${descriptor.characteristic.uuid} notifications")
            } else {
                val message = gattStatusDescription(status)
                log("Failed to subscribe to ${descriptor.characteristic.uuid}: $message")
                _lastError.value = message
            }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                log("Write to ${characteristic.uuid} acknowledged")
            } else {
                val message = gattStatusDescription(status)
                log("Write to ${characteristic.uuid} failed: $message")
                _lastError.value = message
            }
        }

        // Android 13+ (API 33) delivery path.
        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            handleIncoming(characteristic.uuid, value)
        }

        // Pre-Android 13 delivery path. The two-arg overload is only invoked
        // by the framework on API < 33; the three-arg one above takes over
        // from API 33 onward, so this one guards itself to avoid double
        // handling on newer OS versions that may still call both.
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                handleIncoming(characteristic.uuid, characteristic.value ?: return)
            }
        }
    }

    private fun handleIncoming(uuid: UUID, value: ByteArray) {
        if (uuid != TX_CHARACTERISTIC_UUID) return
        val text = value.toString(Charsets.UTF_8)
        log("Received ${value.size} bytes on TX: $text")
        _messages.value = _messages.value +
            ChatMessage(direction = ChatMessage.Direction.RECEIVED, sender = _targetName.value, text = text)
    }

    override fun onCleared() {
        cancelConnectTimeout()
        closeGatt()
        stopScanning()
    }
}
