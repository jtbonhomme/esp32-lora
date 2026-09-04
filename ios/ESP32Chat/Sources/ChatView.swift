import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var ble: BLEManager
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(ble.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: ble.messages) { newValue in
                    guard let last = newValue.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Divider()

            HStack(alignment: .bottom) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit(sendDraft)

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(ble.targetName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Disconnect", role: .destructive) {
                    ble.disconnect()
                }
            }
        }
    }

    private func sendDraft() {
        ble.send(text: draft)
        draft = ""
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.direction == .sent { Spacer(minLength: 40) }

            VStack(alignment: message.direction == .sent ? .trailing : .leading, spacing: 2) {
                Text(message.sender)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .padding(10)
                    .background(message.direction == .sent ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(message.direction == .sent ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if message.direction == .received { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    NavigationStack {
        ChatView()
            .environmentObject(BLEManager())
    }
}
