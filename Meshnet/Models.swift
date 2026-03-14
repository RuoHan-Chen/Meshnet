import Foundation

struct MeshPayload: Codable {
    let id: UUID
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let type: PayloadType
    var targetMessageId: UUID?
    
    // GPS Coordinates for the mesh
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
    var latitude: Double?
    var longitude: Double?
}
