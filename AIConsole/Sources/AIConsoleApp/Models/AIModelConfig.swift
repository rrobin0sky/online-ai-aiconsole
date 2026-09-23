import Foundation

public enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case deepseek = "DeepSeek"
    case ollama = "本地离线模型 (Ollama / Local)"
    case openai = "OpenAI"
    case claude = "Claude (Anthropic)"
    case custom = "自定义 (OpenAI Compatible)"
    
    public var id: String { rawValue }
    
    public var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .openai: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .custom: return "https://api.example.com/v1"
        }
    }
    
    public var defaultModelName: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .ollama: return "qwen2.5-coder"
        case .openai: return "gpt-4o"
        case .claude: return "claude-3-5-sonnet-20241022"
        case .custom: return "default-model"
        }
    }
}

public struct AIModelConfig: Codable, Identifiable {
    public var id: UUID = UUID()
    public var provider: AIProviderType = .deepseek
    public var baseURL: String = AIProviderType.deepseek.defaultBaseURL
    public var apiKey: String = ""
    public var modelName: String = AIProviderType.deepseek.defaultModelName
    public var temperature: Double = 0.3
    public var maxTokens: Int = 2048
    
    private static let keychainApiKeyIdentifier = "com.robin.aiconsole.ai.apikey"
    
    public init(
        id: UUID = UUID(),
        provider: AIProviderType = .deepseek,
        baseURL: String = AIProviderType.deepseek.defaultBaseURL,
        apiKey: String = "",
        modelName: String = AIProviderType.deepseek.defaultModelName,
        temperature: Double = 0.3,
        maxTokens: Int = 2048
    ) {
        self.id = id
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
    
    private static var configFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AIConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("ai_config.json")
    }
    
    public func save() {
        // 1. Securely save API Key to Apple Keychain
        if !apiKey.isEmpty {
            KeychainHelper.shared.save(key: Self.keychainApiKeyIdentifier, secret: apiKey)
        } else {
            KeychainHelper.shared.delete(key: Self.keychainApiKeyIdentifier)
        }
        
        // 2. Save config JSON (excluding raw key)
        var toSave = self
        toSave.apiKey = ""
        if let data = try? JSONEncoder().encode(toSave) {
            try? data.write(to: Self.configFileURL)
        }
    }
    
    public static func load() -> AIModelConfig {
        var config = AIModelConfig()
        if let data = try? Data(contentsOf: configFileURL),
           let saved = try? JSONDecoder().decode(AIModelConfig.self, from: data) {
            config = saved
        }
        
        // Restore API Key from Apple Keychain
        if let storedKey = KeychainHelper.shared.read(key: keychainApiKeyIdentifier) {
            config.apiKey = storedKey
        }
        return config
    }
}
