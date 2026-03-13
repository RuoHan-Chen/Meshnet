//
//  MultipeerManager.swift
//  Meshnet
//
//  Created by Jeremiah Webb on 3/13/26.
//

import Foundation
import MultipeerConnectivity
import Combine

class MultipeerManager: NSObject, ObservableObject {
    // The service type must be a unique string, at most 15 characters long.
    private let serviceType = "p2p-chat"
    
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var messages: [String] = []
    
    override init() {
        super.init()
        
        // 1. Setup Session
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // 2. Setup Advertiser (broadcasts your presence)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        // 3. Setup Browser (looks for other devices)
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
            print("Error sending data: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let text = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.messages.append("\(peerID.displayName): \(text)")
            }
        }
    }
    
    // Required stubs for MCSessionDelegate (unused in this basic example)
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Automatically accept all invitations for this basic demo
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Automatically invite any peer we find
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Handle lost peer if necessary
    }
}
