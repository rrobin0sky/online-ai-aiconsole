import Foundation

public struct SnippetItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var title: String
    public var command: String
    public var category: String
    public var description: String?
    
    public init(
        id: UUID = UUID(),
        title: String,
        command: String,
        category: String = "常用运维",
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.category = category
        self.description = description
    }
}
