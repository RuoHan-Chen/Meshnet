import Foundation
import MultipeerConnectivity
import Combine
import SwiftUI

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "p2p-mesh" // Kept under 15 chars
    
    private var myPeerId: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    // The device's unique ID for mesh routing
    @AppStorage("deviceId") private var deviceId: String = UUID().uuidString
    @AppStorage("username") var username: String = UIDevice.current.name {
        didSet { restartSession() } // Restart mesh if name changes
    }
    
    @Published var connectedPeers: [MCPeerID] = []
    
    // Cache array: Automatically save to UserDefaults whenever this array changes
    @Published var messages: [LocalMessage] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(messages) {
                UserDefaults.standard.set(encoded, forKey: "meshHistory")
            }
        }
    }
    
    // Mesh Routing State: Keep track of what we've seen so we don't infinitely loop
    private var processedPayloadIDs: Set<UUID> = []
    
    override init() {
        super.init()
        loadHistory()
        setupSession()
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "meshHistory"),
           let saved = try? JSONDecoder().decode([LocalMessage].self, from: data) {
            self.messages = saved
            self.processedPayloadIDs = Set(saved.map { $0.id })
        }
    }
    
    private func setupSession() {
            // 1. Clean the string and check if it's empty
            var safeName = username.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 2. Provide a fallback if it is empty
            if safeName.isEmpty {
                safeName = UIDevice.current.name
                // If even the device name is empty for some reason, force a default
                if safeName.isEmpty {
                    safeName = "User-\(Int.random(in: 1000...9999))"
                }
            }
            
            // MCPeerID also crashes if the name is over 63 bytes, so we cap it safely
            let finalName = String(safeName.prefix(30))
            
            // 3. Initialize with our guaranteed-safe name
            myPeerId = MCPeerID(displayName: finalName)
            session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            
            browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
        }
    
    func restartSession() {
        session?.disconnect()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        setupSession()
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.messages.removeAll()
            self.processedPayloadIDs.removeAll()
        }
    }
    
    // MARK: - Sending Logic
    func sendMessage(text: String) {
        let newId = UUID()
        // 1. Create the over-the-air payload
        let payload = MeshPayload(id: newId, senderId: deviceId, senderName: username, content: text, timestamp: Date(), type: .chatMessage, isRelayed: false)
        
        // 2. Create the local UI version (isRelayed is obviously false for your own messages)
        let localMsg = LocalMessage(id: newId, senderId: deviceId, senderName: username, content: text, timestamp: payload.timestamp, isMe: true, status: .sent)
        
        DispatchQueue.main.async {
            self.messages.append(localMsg)
            self.processedPayloadIDs.insert(newId)
        }
        
        broadcast(payload: payload)
    }
    
    private func broadcast(payload: MeshPayload, excludePeer: MCPeerID? = nil) {
        let peersToReceive = session.connectedPeers.filter { $0 != excludePeer }
        guard !peersToReceive.isEmpty else { return }
        
        if let data = try? JSONEncoder().encode(payload) {
            try? session.send(data, toPeers: peersToReceive, with: .reliable)
        }
    }
    
    private func sendReceipt(for targetId: UUID) {
        let receipt = MeshPayload(id: UUID(), senderId: deviceId, senderName: username, content: "", timestamp: Date(), type: .deliveryReceipt, targetMessageId: targetId, isRelayed: false)
        broadcast(payload: receipt)
    }
}

// MARK: - Multipeer Delegates
extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.connectedPeers = session.connectedPeers }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(MeshPayload.self, from: data) else { return }
        
        // Flooding Protocol: Stop if we've already processed this exact payload to prevent infinite loops
        guard !processedPayloadIDs.contains(payload.id) else { return }
        processedPayloadIDs.insert(payload.id)
        
        DispatchQueue.main.async {
            if payload.type == .chatMessage {
                
                // Determine if it was relayed based on whether the original author matches the device that handed it to us
                let messageWasRelayed = (payload.senderName != peerID.displayName)
                
                // 1. Save and show the message
                let newMsg = LocalMessage(id: payload.id, senderId: payload.senderId, senderName: payload.senderName, content: payload.content, timestamp: payload.timestamp, isMe: false, status: .delivered)
                
                self.messages.append(newMsg)
                
                // 2. Relay the message to other mesh nodes
                self.broadcast(payload: payload, excludePeer: peerID)
                
                // 3. Fire back a delivery receipt through the mesh
                self.sendReceipt(for: payload.id)
                
            } else if payload.type == .deliveryReceipt {
                // 1. Find the original message and mark it delivered
                if let targetId = payload.targetMessageId,
                   let index = self.messages.firstIndex(where: { $0.id == targetId }) {
                    self.messages[index].status = .delivered
                }
                // 2. Relay the receipt through the mesh
                self.broadcast(payload: payload, excludePeer: peerID)
            }
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
            // When a device drops out of range, log it and force the browser to keep looking
            print("Lost track of \(peerID.displayName)")
            
            // Optional: If you want to force a mini-refresh when someone drops
            // to ensure the mesh heals around the missing node:
            browser.stopBrowsingForPeers()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                browser.startBrowsingForPeers()
            }
        }
    
    // Required Stubs
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
