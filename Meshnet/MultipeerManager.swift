import Foundation
import MultipeerConnectivity
import Combine // Required for ObservableObject and @Published

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "p2p-chat"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    @Published var connectedPeers: [MCPeerID] = []
    
    // Cache: Automatically save to UserDefaults whenever this array changes
    @Published var messages: [String] = [] {
        didSet {
            UserDefaults.standard.set(messages, forKey: "chatHistory")
        }
    }
    
    override init() {
        super.init()
        
        // Load existing cache on startup
        if let savedMessages = UserDefaults.standard.stringArray(forKey: "chatHistory") {
            self.messages = savedMessages
        }
        
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
    
    func send(text: String) {
        guard !session.connectedPeers.isEmpty else { return }
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            DispatchQueue.main.async {
                self.messages.append("Me: \(text)")
            }
        } catch {
            print("Error sending: \(error.localizedDescription)")
        }
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.messages.removeAll()
        }
    }
}

extension MultipeerManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.connectedPeers = session.connectedPeers }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let text = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async { self.messages.append("\(peerID.displayName): \(text)") }
        }
    }
    
    // Standard required stubs
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
