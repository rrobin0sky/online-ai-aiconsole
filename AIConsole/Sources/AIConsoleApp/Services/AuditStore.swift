import Foundation
import Combine

public struct AuditLogEntry: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let command: String
    public let riskLevel: String
    public let sessionName: String
    public let targetHost: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        command: String,
        riskLevel: String,
        sessionName: String,
        targetHost: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.command = command
        self.riskLevel = riskLevel
        self.sessionName = sessionName
        self.targetHost = targetHost
    }
}

@MainActor
public final class AuditStore: ObservableObject {
    public static let shared = AuditStore()
    
    @Published public var logs: [AuditLogEntry] = []
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AIConsole", isDirectory: true)
        self.fileURL = appDir.appendingPathComponent("audit_log.json")
        load()
    }
    
    public func logExecution(command: String, riskLevel: String = "Safe", sessionName: String = "Default", targetHost: String = "127.0.0.1") {
        let entry = AuditLogEntry(
            command: command,
            riskLevel: riskLevel,
            sessionName: sessionName,
            targetHost: targetHost
        )
        logs.insert(entry, at: 0)
        save()
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([AuditLogEntry].self, from: data) else { return }
        self.logs = list
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        try? data.write(to: fileURL)
    }
}
