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
    
    // Beacon Management
    private var beaconTimer: AnyCancellable?

    // GPS and Compass
    private let locationManager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var currentHeading: Double = 0
    
    @AppStorage("deviceId") private var deviceId: String = UUID().uuidString
    @AppStorage("username") var username: String = UIDevice.current.name {
        didSet { restartSession() }
    }
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var peerRegistry: [String: LocalMessage] = [:]
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
        startBeacon() // Initialize the background heartbeat
    }
    
    // MARK: - Thread-Safe Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "meshHistory"),
           let saved = try? JSONDecoder().decode([LocalMessage].self, from: data) {
            DispatchQueue.main.async {
                self.messages = saved
                self.processedPayloadIDs = Set(saved.map { $0.id })
                for msg in saved where !msg.isMe {
                    self.peerRegistry[msg.senderId] = msg
                }
            }
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

    // MARK: - Beacon Logic
    private func startBeacon() {
        beaconTimer = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendBeacon()
            }
    }

    private func sendBeacon() {
        // Only beacon if we have peers to talk to
        guard !session.connectedPeers.isEmpty else { return }
        
        let beacon = MeshPayload(
            id: UUID(),
            senderId: deviceId,
            senderName: username,
            content: "BEACON_PING",
            timestamp: Date(),
            type: .chatMessage,
            latitude: lastLocation?.coordinate.latitude,
            longitude: lastLocation?.coordinate.longitude
        )
        broadcast(payload: beacon)
    }
    
    // MARK: - Communication logic
    func restartSession() {
        session?.disconnect()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.setupSession() }
    }
    
    func sendMessage(text: String) {
        let newId = UUID()
        let payload = MeshPayload(
            id: newId, senderId: deviceId, senderName: username,
            content: text, timestamp: Date(), type: .chatMessage,
            latitude: lastLocation?.coordinate.latitude,
            longitude: lastLocation?.coordinate.longitude
        )
        
        let localMsg = LocalMessage(
            id: newId, senderId: deviceId, senderName: username,
            content: text, timestamp: payload.timestamp, isMe: true,
            status: .sent, latitude: payload.latitude, longitude: payload.longitude
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
            self.peerRegistry.removeAll()
        }
    }
}

// MARK: - Delegates and Thread-Safe Updates
extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async {
            self.lastLocation = locations.last
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.currentHeading = newHeading.trueHeading
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(MeshPayload.self, from: data) else { return }
        
        // Avoid duplicate processing
        if processedPayloadIDs.contains(payload.id) { return }
        processedPayloadIDs.insert(payload.id)
        
        DispatchQueue.main.async {
            // Handle silent beacon update
            if payload.content == "BEACON_PING" {
                let update = LocalMessage(
                    id: payload.id, senderId: payload.senderId, senderName: payload.senderName,
                    content: "[Location Update]", timestamp: payload.timestamp, isMe: false,
                    status: .delivered, isRelayed: false,
                    latitude: payload.latitude, longitude: payload.longitude
                )
                self.peerRegistry[payload.senderId] = update
                // Still relay the beacon through the mesh!
                self.broadcast(payload: payload, excludePeer: peerID)
                return
            }

            if payload.type == .chatMessage {
                let isRelayed = (payload.senderName != peerID.displayName)
                let newMsg = LocalMessage(
                    id: payload.id, senderId: payload.senderId, senderName: payload.senderName,
                    content: payload.content, timestamp: payload.timestamp, isMe: false,
                    status: .delivered, isRelayed: isRelayed,
                    latitude: payload.latitude, longitude: payload.longitude
                )
                self.messages.append(newMsg)
                self.peerRegistry[payload.senderId] = newMsg
                self.broadcast(payload: payload, excludePeer: peerID)
                self.sendReceipt(for: payload.id)
            } else if payload.type == .deliveryReceipt {
                if let targetId = payload.targetMessageId, let index = self.messages.firstIndex(where: { $0.id == targetId }) {
                    self.messages[index].status = .delivered
                }
                self.broadcast(payload: payload, excludePeer: peerID)
            }
        }
    }
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost track of \(peerID.displayName). Cleaning up...")
        
        DispatchQueue.main.async {
            self.peerRegistry.removeValue(forKey: peerID.displayName)
            self.connectedPeers = self.session.connectedPeers
            
            // Re-trigger discovery to clear zombie connections
            self.browser.stopBrowsingForPeers()
            self.advertiser.stopAdvertisingPeer()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.browser.startBrowsingForPeers()
                self.advertiser.startAdvertisingPeer()
            }
        }
    }
    
    // Unused MCSession Delegates
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// Math Extensions
extension CLLocation {
    func bearing(to destination: CLLocation) -> Double {
        let lat1 = self.coordinate.latitude * .pi / 180
        let lon1 = self.coordinate.longitude * .pi / 180
        let lat2 = destination.coordinate.latitude * .pi / 180
        let lon2 = destination.coordinate.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
