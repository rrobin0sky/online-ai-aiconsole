import Foundation

public struct WorkspaceTab: Identifiable, Equatable {
    public let id: UUID
    public var session: SessionItem
    public var title: String
    public var currentDirectory: String
    public var connectedAt: Date
    public var isConnected: Bool
    
    public init(
        id: UUID = UUID(),
        session: SessionItem,
        title: String? = nil,
        currentDirectory: String = "~",
        connectedAt: Date = Date(),
        isConnected: Bool = true
    ) {
        self.id = id
        self.session = session
        self.title = title ?? session.name
        self.currentDirectory = currentDirectory
        self.connectedAt = connectedAt
        self.isConnected = isConnected
    }
    
    public var uptimeFormatted: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(connectedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        if minutes < 60 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            let hours = minutes / 60
            let remMin = minutes % 60
            return String(format: "%02d:%02d:%02d", hours, remMin, seconds)
        }
    }
    
    public static func == (lhs: WorkspaceTab, rhs: WorkspaceTab) -> Bool {
        lhs.id == rhs.id
    }
}
