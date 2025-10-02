import Foundation

struct LocationSample: Codable, Hashable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date

    init(id: UUID = UUID(), latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date = Date()) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

struct LocationRequest: Codable, Identifiable, Hashable {
    let id: UUID
    let issuedAt: Date

    init(id: UUID = UUID(), issuedAt: Date = Date()) {
        self.id = id
        self.issuedAt = issuedAt
    }
}

enum BLEProtocol {
    static let serviceUUID = "DA5B28D3-9273-40C5-9D76-FA9A393F40C4"
    static let requestCharacteristicUUID = "356A92F8-CB12-4B99-96C4-4C9470200F94"
    static let responseCharacteristicUUID = "10FDD78C-D272-4672-A4AA-4C3FB34CF0E9"
}

enum LocationWireCodec {
    static func encode(_ sample: LocationSample) throws -> Data {
        try JSONEncoder().encode(sample)
    }

    static func decodeSample(from data: Data) throws -> LocationSample {
        try JSONDecoder().decode(LocationSample.self, from: data)
    }

    static func encode(_ request: LocationRequest) throws -> Data {
        try JSONEncoder().encode(request)
    }

    static func decodeRequest(from data: Data) throws -> LocationRequest {
        try JSONDecoder().decode(LocationRequest.self, from: data)
    }
}
