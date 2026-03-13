import Foundation
import MultipeerConnectivity
import Combine
import SwiftUI
import CoreLocation

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "p2p-mesh"
    
    private var myPeerId: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    // GPS Management
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    
    @AppStorage("deviceId") private var deviceId: String = UUID().uuidString
    @AppStorage("username") var username: String = UIDevice.current.name {
        didSet { restartSession() }
    }
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var messages: [LocalMessage] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(messages) {
                UserDefaults.standard.set(encoded, forKey: "meshHistory")
            }
        }
    }
    
    private var processedPayloadIDs: Set<UUID> = []
    
    override init() {
        super.init()
        loadHistory()
        setupLocationManager()
        setupSession()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "meshHistory"),
           let saved = try? JSONDecoder().decode([LocalMessage].self, from: data) {
            self.messages = saved
            self.processedPayloadIDs = Set(saved.map { $0.id })
        }
    }
    
    private func setupSession() {
        var safeName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeName.isEmpty { safeName = UIDevice.current.name }
        let finalName = String(safeName.prefix(30))
        
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupSession()
        }
    }
    
    func sendMessage(text: String) {
        let newId = UUID()
        // Attach current GPS to the payload
        let payload = MeshPayload(
            id: newId,
            senderId: deviceId,
            senderName: username,
            content: text,
            timestamp: Date(),
            type: .chatMessage,
            latitude: lastLocation?.coordinate.latitude,
            longitude: lastLocation?.coordinate.longitude
        )
        
        let localMsg = LocalMessage(
            id: newId,
            senderId: deviceId,
            senderName: username,
            content: text,
            timestamp: payload.timestamp,
            isMe: true,
            status: .sent,
            isRelayed: false,
            latitude: payload.latitude,
            longitude: payload.longitude
        )
        
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
        let receipt = MeshPayload(id: UUID(), senderId: deviceId, senderName: username, content: "", timestamp: Date(), type: .deliveryReceipt, targetMessageId: targetId)
        broadcast(payload: receipt)
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.messages.removeAll()
            self.processedPayloadIDs.removeAll()
        }
    }
}

// MARK: - Delegates
extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.lastLocation = locations.last
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(MeshPayload.self, from: data) else { return }
        guard !processedPayloadIDs.contains(payload.id) else { return }
        processedPayloadIDs.insert(payload.id)
        
        DispatchQueue.main.async {
            if payload.type == .chatMessage {
                let messageWasRelayed = (payload.senderName != peerID.displayName)
                let newMsg = LocalMessage(
                    id: payload.id,
                    senderId: payload.senderId,
                    senderName: payload.senderName,
                    content: payload.content,
                    timestamp: payload.timestamp,
                    isMe: false,
                    status: .delivered,
                    isRelayed: messageWasRelayed,
                    latitude: payload.latitude,
                    longitude: payload.longitude
                )
                self.messages.append(newMsg)
                self.broadcast(payload: payload, excludePeer: peerID)
                self.sendReceipt(for: payload.id)
            } else if payload.type == .deliveryReceipt {
                if let targetId = payload.targetMessageId,
                   let index = self.messages.firstIndex(where: { $0.id == targetId }) {
                    self.messages[index].status = .delivered
                }
                self.broadcast(payload: payload, excludePeer: peerID)
            }
        }
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.connectedPeers = session.connectedPeers }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        browser.stopBrowsingForPeers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { browser.startBrowsingForPeers() }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
