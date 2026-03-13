import Foundation

struct MeshPayload: Codable {
    let id: UUID
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let type: PayloadType
    var targetMessageId: UUID?
    
    // NEW: GPS Coordinates for Disaster Relief Map
    var latitude: Double?
    var longitude: Double?
    
    enum PayloadType: String, Codable {
        case chatMessage
        case deliveryReceipt
    }
}

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
    
    // Store coordinates locally for the UI
    var latitude: Double?
    var longitude: Double?
}
