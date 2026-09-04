import SwiftUI
import UIKit

struct DebugLogView: View {
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if ble.debugLog.isEmpty {
                    ContentUnavailableFallback()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(ble.debugLog.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                        .id(index)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: ble.debugLog.count) { _ in
                            guard let lastIndex = ble.debugLog.indices.last else { return }
                            withAnimation { proxy.scrollTo(lastIndex, anchor: .bottom) }
                        }
                        .onAppear {
                            guard let lastIndex = ble.debugLog.indices.last else { return }
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = ble.debugLog.joined(separator: "\n")
                        } label: {
                            Label("Copy log", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            ble.clearDebugLog()
                        } label: {
                            Label("Clear log", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct ContentUnavailableFallback: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "ladybug")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No log entries yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DebugLogView()
        .environmentObject(BLEManager())
}
