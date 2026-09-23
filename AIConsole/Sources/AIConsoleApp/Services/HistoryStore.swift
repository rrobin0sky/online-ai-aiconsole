import Foundation
import Combine

@MainActor
public final class HistoryStore: ObservableObject {
    public static let shared = HistoryStore()
    
    @Published public var records: [HistoryRecord] = []
    
    private let maxLimit = 500
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AIConsole", isDirectory: true)
        self.fileURL = appDir.appendingPathComponent("history.json")
        load()
    }
    
    public func record(sessionId: UUID, command: String, exitCode: Int32? = nil) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let newRecord = HistoryRecord(sessionId: sessionId, command: trimmed, exitCode: exitCode)
        records.insert(newRecord, at: 0)
        
        if records.count > maxLimit {
            records = Array(records.prefix(maxLimit))
        }
        save()
    }
    
    public func search(query: String) -> [HistoryRecord] {
        if query.isEmpty { return records }
        return records.filter { $0.command.localizedCaseInsensitiveContains(query) }
    }
    
    public func clear() {
        records.removeAll()
        save()
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([HistoryRecord].self, from: data) else { return }
        self.records = list
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL)
    }
}
