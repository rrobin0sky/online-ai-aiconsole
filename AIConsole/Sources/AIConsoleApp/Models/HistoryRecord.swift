import Foundation

public struct HistoryRecord: Identifiable, Codable, Hashable {
    public let id: UUID
    public let sessionId: UUID
    public let command: String
    public let timestamp: Date
    public let exitCode: Int32?
    
    public init(id: UUID = UUID(), sessionId: UUID, command: String, timestamp: Date = Date(), exitCode: Int32? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.command = command
        self.timestamp = timestamp
        self.exitCode = exitCode
    }
}
