import Foundation

struct StatusLog: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String

    init(message: String, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.message = message
    }
}
