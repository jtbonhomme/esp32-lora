package com.jtbonhomme.esp32chat.ble

import android.bluetooth.BluetoothDevice
import java.util.Date
import java.util.UUID

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val direction: Direction,
    val sender: String,
    val text: String,
    val date: Date = Date()
) {
    enum class Direction { SENT, RECEIVED }
}

/**
 * A peripheral discovered by [BleViewModel]. Scanning is already filtered
 * to [BleViewModel.SERVICE_UUID] at the OS level, so anything reaching this
 * class is running sketches/ble firmware — [isTargetMatch] only controls
 * whether it's highlighted as the configured target, not whether it's shown
 * at all (a board's actual BLE_NAME can drift out of sync with the app's
 * configured name).
 */
data class DiscoveredDevice(
    val id: String, // MAC address
    val device: BluetoothDevice,
    val name: String,
    val rssi: Int,
    val isTargetMatch: Boolean
)

sealed class ConnectionState {
    data object Idle : ConnectionState()
    data object Scanning : ConnectionState()
    data class Connecting(val name: String) : ConnectionState()
    data class Connected(val name: String) : ConnectionState()
    data object Disconnected : ConnectionState()
    data class BluetoothUnavailable(val reason: String) : ConnectionState()
}
