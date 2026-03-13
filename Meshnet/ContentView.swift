import SwiftUI

struct ContentView: View {
    @StateObject private var multipeerManager = MultipeerManager()
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            // Header: Connection Status & Clear Button
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(multipeerManager.connectedPeers.isEmpty ? Color.red : Color.green)
                        .frame(width: 10, height: 10)
                    
                    Text("Peers: \(multipeerManager.connectedPeers.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer() // Pushes items to opposite sides
                
                Button(action: {
                    multipeerManager.clearHistory()
                }) {
                    Text("Clear Chat")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider().padding(.vertical, 8)
            
            // Message List (with iOS 17+ auto-scroll)
            ScrollViewReader { proxy in
                List(multipeerManager.messages, id: \.self) { message in
                    Text(message)
                }
                .onChange(of: multipeerManager.messages) { oldValue, newValue in
                    // Scroll to the newest message whenever the array updates
                    if let last = newValue.last {
                        proxy.scrollTo(last)
                    }
                }
            }
            
            // Input Area
            HStack {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: {
                    let trimmedText = messageText.trimmingCharacters(in: .whitespaces)
                    guard !trimmedText.isEmpty else { return }
                    multipeerManager.send(text: trimmedText)
                    messageText = ""
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                        .foregroundColor(multipeerManager.connectedPeers.isEmpty ? .gray : .blue)
                }
                .disabled(multipeerManager.connectedPeers.isEmpty)
            }
            .padding()
        }
    }
}
