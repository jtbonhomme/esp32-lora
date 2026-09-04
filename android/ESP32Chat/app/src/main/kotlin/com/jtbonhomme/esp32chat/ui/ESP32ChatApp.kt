package com.jtbonhomme.esp32chat.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.jtbonhomme.esp32chat.ble.BleViewModel
import com.jtbonhomme.esp32chat.ble.ConnectionState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ESP32ChatApp(
    viewModel: BleViewModel,
    permissionsGranted: Boolean,
    onRequestPermissions: () -> Unit
) {
    val state by viewModel.state.collectAsState()
    var showSettings by remember { mutableStateOf(false) }
    var showDebugLog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("ESP32 Chat") },
                actions = {
                    IconButton(onClick = { showDebugLog = true }) {
                        Icon(Icons.Default.BugReport, contentDescription = "Debug Log")
                    }
                    IconButton(onClick = { showSettings = true }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when {
                !permissionsGranted -> PermissionRequiredScreen(onRequestPermissions)
                state is ConnectionState.Connected -> ChatScreen(viewModel)
                else -> ScanListScreen(viewModel)
            }
        }
    }

    if (showSettings) {
        SettingsSheet(viewModel = viewModel, onDismiss = { showSettings = false })
    }
    if (showDebugLog) {
        DebugLogSheet(viewModel = viewModel, onDismiss = { showDebugLog = false })
    }
}

@Composable
private fun PermissionRequiredScreen(onRequestPermissions: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            "Bluetooth permission is required to find and connect to your ESP32 board.",
            style = MaterialTheme.typography.bodyMedium
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = onRequestPermissions) { Text("Grant permission") }
    }
}
