//
//  Models.swift
//  Meshnet
//
//  Created by Jeremiah Webb on 3/13/26.
//

import Foundation

// The JSON data we send over the air
struct MeshPayload: Codable {
    let id: UUID
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let type: PayloadType
    var targetMessageId: UUID? // Used to identify which message a receipt belongs to
    var isRelayed: Bool = false// <-- Add this new property
    
    enum PayloadType: String, Codable {
        case chatMessage
        case deliveryReceipt
    }
}

// The local object we use for our SwiftUI view
enum DeliveryStatus: String, Codable {
    case sent
    case delivered
}

struct LocalMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let isMe: Bool
    var status: DeliveryStatus
    var isRelayed: Bool = false
}
