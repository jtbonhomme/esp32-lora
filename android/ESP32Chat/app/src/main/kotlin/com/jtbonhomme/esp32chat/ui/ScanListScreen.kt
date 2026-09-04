package com.jtbonhomme.esp32chat.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jtbonhomme.esp32chat.ble.BleViewModel
import com.jtbonhomme.esp32chat.ble.ConnectionState
import com.jtbonhomme.esp32chat.ble.DiscoveredDevice

@Composable
fun ScanListScreen(viewModel: BleViewModel) {
    val state by viewModel.state.collectAsState()
    val devices by viewModel.discoveredDevices.collectAsState()
    val targetName by viewModel.targetName.collectAsState()
    val lastError by viewModel.lastError.collectAsState()

    val matching = devices.filter { it.isTargetMatch }
    val others = devices.filter { !it.isTargetMatch }

    Column(modifier = Modifier.fillMaxSize()) {
        StatusHeader(state)

        lastError?.let { error ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            ) {
                Icon(
                    Icons.Default.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 2.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }

        when {
            state is ConnectionState.BluetoothUnavailable -> Unit
            devices.isEmpty() -> EmptyState(targetName)
            else -> {
                LazyColumn(modifier = Modifier.fillMaxWidth()) {
                    if (matching.isNotEmpty()) {
                        item { SectionHeader("Matches “$targetName”") }
                        items(matching, key = { it.id }) { device ->
                            DeviceRow(device, onConnect = { viewModel.connect(device) })
                        }
                    }
                    if (others.isNotEmpty()) {
                        item { SectionHeader("Other ESP32 Chat devices nearby") }
                        items(others, key = { it.id }) { device ->
                            DeviceRow(device, onConnect = { viewModel.connect(device) })
                        }
                        item {
                            Text(
                                "These run the same firmware but advertise a different name than “$targetName”. " +
                                    "Connect anyway, or update the name in Settings to match.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(16.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyState(targetName: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(modifier = Modifier.height(12.dp))
            Text("Looking for “$targetName”…")
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "No BLE devices advertising the ESP32 Chat service seen yet. Make sure the board is " +
                    "flashed with sketches/ble (check its serial monitor for an “advertising as…” line).",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 32.dp)
            )
        }
    }
}

@Composable
private fun StatusHeader(state: ConnectionState) {
    val (text, color) = when (state) {
        is ConnectionState.BluetoothUnavailable -> state.reason to MaterialTheme.colorScheme.error
        is ConnectionState.Connecting -> "Connecting to ${state.name}…" to MaterialTheme.colorScheme.onSurface
        ConnectionState.Disconnected -> "Disconnected — rescanning" to Color(0xFFB26A00)
        else -> return
    }
    Text(text, color = color, modifier = Modifier.padding(16.dp))
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

@Composable
private fun DeviceRow(device: DiscoveredDevice, onConnect: () -> Unit) {
    ListItem(
        headlineContent = { Text(device.name) },
        supportingContent = { Text("RSSI ${device.rssi} dBm") },
        trailingContent = { TextButton(onClick = onConnect) { Text("Connect") } }
    )
    HorizontalDivider()
}
