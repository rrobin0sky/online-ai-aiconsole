import Foundation

public enum CommandRiskLevel: String, Codable {
    case safe = "Safe"
    case caution = "Caution"
    case dangerous = "Dangerous"
    
    public var iconName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .dangerous: return "xmark.octagon.fill"
        }
    }
}

public struct AICommandCard: Identifiable, Codable {
    public let id: UUID
    public let command: String
    public let explanation: String
    public let riskLevel: CommandRiskLevel
    public var executed: Bool
    
    public init(
        id: UUID = UUID(),
        command: String,
        explanation: String,
        riskLevel: CommandRiskLevel = .safe,
        executed: Bool = false
    ) {
        self.id = id
        self.command = command
        self.explanation = explanation
        self.riskLevel = riskLevel
        self.executed = executed
    }
}
