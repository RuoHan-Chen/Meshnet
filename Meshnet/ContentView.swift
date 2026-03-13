import SwiftUI

struct ContentView: View {
    @StateObject private var manager = MultipeerManager()
    @State private var messageText = ""
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Circle()
                        .fill(manager.connectedPeers.isEmpty ? Color.red : Color.green)
                        .frame(width: 10, height: 10)
                    Text("Mesh Nodes: \(manager.connectedPeers.count)")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                
                Divider().padding(.top, 8)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(manager.messages) { msg in
                                MessageBubble(message: msg)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: manager.messages) { _, newValue in
                        if let last = newValue.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                
                HStack {
                    TextField("Disaster Alert...", text: $messageText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {
                        let trimmed = messageText.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        manager.sendMessage(text: trimmed)
                        messageText = ""
                    }) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(manager.connectedPeers.isEmpty ? .gray : .orange)
                    }
                    .disabled(manager.connectedPeers.isEmpty)
                }
                .padding()
                .background(Color(UIColor.systemGray6))
            }
            .navigationTitle("Disaster Mesh")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { manager.clearHistory() }.foregroundColor(.red)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { manager.restartSession() }) { Image(systemName: "arrow.clockwise") }
                    Button(action: { showingSettings.toggle() }) { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(manager: manager, isPresented: $showingSettings)
            }
        }
    }
}

struct MessageBubble: View {
    let message: LocalMessage
    
    var body: some View {
        HStack {
            if message.isMe { Spacer() }
            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(message.senderName).font(.caption2).bold()
                    if message.isRelayed {
                        Image(systemName: "network").font(.system(size: 9)).foregroundColor(.orange)
                    }
                }
                
                Text(message.content)
                    .padding(10)
                    .background(message.isMe ? Color.blue : Color(UIColor.systemGray5))
                    .foregroundColor(message.isMe ? .white : .primary)
                    .cornerRadius(12)
                
                // NEW: Coordinates Display
                if let lat = message.latitude, let lon = message.longitude {
                    Text(String(format: "Loc: %.4f, %.4f", lat, lon))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            if !message.isMe { Spacer() }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var manager: MultipeerManager
    @Binding var isPresented: Bool
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Identify Yourself")) {
                    TextField("Username", text: $manager.username)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { isPresented = false } }
        }
    }
}
