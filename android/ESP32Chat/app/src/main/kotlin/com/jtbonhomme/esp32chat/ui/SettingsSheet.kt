package com.jtbonhomme.esp32chat.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.jtbonhomme.esp32chat.ble.BleViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(viewModel: BleViewModel, onDismiss: () -> Unit) {
    val currentTarget by viewModel.targetName.collectAsState()
    val currentSender by viewModel.senderName.collectAsState()
    var targetDraft by remember { mutableStateOf(currentTarget) }
    var senderDraft by remember { mutableStateOf(currentSender) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(modifier = Modifier.padding(24.dp)) {
            Text("Settings", style = MaterialTheme.typography.titleLarge)
            Spacer(modifier = Modifier.height(16.dp))

            OutlinedTextField(
                value = targetDraft,
                onValueChange = { targetDraft = it },
                label = { Text("ESP32 BLE name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "Must match the BLE_NAME the firmware was built with (default \"Heltec-BLE\").",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 16.dp)
            )

            OutlinedTextField(
                value = senderDraft,
                onValueChange = { senderDraft = it },
                label = { Text("Your name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "Shown on the ESP32's OLED screen next to each message you send.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 16.dp)
            )

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Spacer(modifier = Modifier.width(8.dp))
                Button(onClick = {
                    val trimmedTarget = targetDraft.trim()
                    val trimmedSender = senderDraft.trim()
                    if (trimmedTarget.isNotEmpty() && trimmedTarget != currentTarget) {
                        viewModel.setTargetName(trimmedTarget)
                        viewModel.startScanning()
                    }
                    if (trimmedSender.isNotEmpty()) {
                        viewModel.setSenderName(trimmedSender)
                    }
                    onDismiss()
                }) { Text("Done") }
            }
        }
    }
}
