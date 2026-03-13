import SwiftUI

struct ContentView: View {
    @StateObject private var manager = MultipeerManager()
    @State private var messageText = ""
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection Header
                HStack {
                    Circle()
                        .fill(manager.connectedPeers.isEmpty ? Color.red : Color.green)
                        .frame(width: 10, height: 10)
                    Text("Direct Nodes: \(manager.connectedPeers.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                Divider()
                
                // Chat Area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(manager.messages) { msg in
                                MessageBubble(message: msg)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: manager.messages) { oldValue, newValue in
                        if let last = newValue.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                
                // Input Bar
                HStack {
                    TextField("Message network...", text: $messageText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {
                        let trimmed = messageText.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        manager.sendMessage(text: trimmed)
                        messageText = ""
                    }) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(manager.connectedPeers.isEmpty ? .gray : .blue)
                    }
                    .disabled(manager.connectedPeers.isEmpty)
                }
                .padding()
                .background(Color(UIColor.systemGray6))
            }
            .navigationTitle("MeshChat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { manager.clearHistory() }
                        .foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationView {
                    Form {
                        Section(header: Text("Profile"), footer: Text("Changing your name will briefly disconnect you from the mesh network.")) {
                            TextField("Username", text: $manager.username)
                        }
                    }
                    .navigationTitle("Settings")
                    .toolbar {
                        Button("Done") { showingSettings = false }
                    }
                }
            }
        }
    }
}

// Chat Bubble Subview
struct MessageBubble: View {
    let message: LocalMessage
    
    var body: some View {
        HStack {
            if message.isMe { Spacer() }
            
            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                if !message.isMe {
                    // --- NEW INDICATOR UI ---
                    HStack(spacing: 4) {
                        Text(message.senderName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        
                        Image(systemName: message.isRelayed ? "network" : "arrow.left.arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(message.isRelayed ? .orange : .green)
                        
                        Text(message.isRelayed ? "Relayed" : "Direct")
                            .font(.system(size: 9))
                            .foregroundColor(message.isRelayed ? .orange : .green)
                    }
                    // ------------------------
                }
                
                Text(message.content)
                    .padding(10)
                    .background(message.isMe ? Color.blue : Color(UIColor.systemGray5))
                    .foregroundColor(message.isMe ? .white : .primary)
                    .cornerRadius(16)
                
                if message.isMe {
                    HStack(spacing: 2) {
                        Text(message.status.rawValue.capitalized)
                            .font(.system(size: 10))
                        Image(systemName: message.status == .delivered ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(message.status == .delivered ? .green : .gray)
                }
            }
            
            if !message.isMe { Spacer() }
        }
    }
}
