//
//  ContentView.swift
//  Meshnet
//
//  Created by Jeremiah Webb on 3/13/26.
//
import SwiftUI

struct ContentView: View {
    @StateObject private var multipeerManager = MultipeerManager()
    @State private var messageText = ""
    
    var body: some View {
        VStack {
            // Header: Connection Status
            HStack {
                Circle()
                    .fill(multipeerManager.connectedPeers.isEmpty ? Color.red : Color.green)
                    .frame(width: 10, height: 10)
                Text("Connected Peers: \(multipeerManager.connectedPeers.count)")
                    .font(.headline)
            }
            .padding()
            
            // Message List
            List(multipeerManager.messages, id: \.self) { message in
                Text(message)
            }
            
            // Message Input
            HStack {
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: {
                    guard !messageText.isEmpty else { return }
                    multipeerManager.send(text: messageText)
                    messageText = ""
                }) {
                    Text("Send")
                        .bold()
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(multipeerManager.connectedPeers.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(multipeerManager.connectedPeers.isEmpty)
            }
            .padding()
        }
    }
}
