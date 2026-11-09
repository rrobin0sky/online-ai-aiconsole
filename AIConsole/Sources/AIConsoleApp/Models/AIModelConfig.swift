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

// MARK: - 多大模型预设 Profile
public struct AIModelProfile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var provider: AIProviderType
    public var baseURL: String
    public var apiKey: String
    public var modelName: String
    public var temperature: Double
    public var maxTokens: Int
    
    public init(
        id: UUID = UUID(),
        name: String = "默认模型",
        provider: AIProviderType = .deepseek,
        baseURL: String = AIProviderType.deepseek.defaultBaseURL,
        apiKey: String = "",
        modelName: String = AIProviderType.deepseek.defaultModelName,
        temperature: Double = 0.3,
        maxTokens: Int = 2048
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
    
    public var keychainKey: String {
        "com.robin.aiconsole.ai.profile.\(id.uuidString)"
    }
}

// MARK: - 预设配置持久化存储
public final class AIProfileStore {
    private static let profilesFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AIConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("ai_profiles.json")
    }()
    
    private static let activeProfileKey = "com.robin.aiconsole.ai.active_profile_id"
    private static let legacyConfigFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AIConsole", isDirectory: true).appendingPathComponent("ai_config.json")
    }()
    private static let legacyKeychainApiKeyIdentifier = "com.robin.aiconsole.ai.apikey"
    
    public struct SavedProfilesContainer: Codable {
        public var activeProfileId: UUID
        public var profiles: [AIModelProfile]
    }
    
    public static func load() -> (profiles: [AIModelProfile], activeId: UUID) {
        // 1. 如果已存在新的预设配置文件
        if let data = try? Data(contentsOf: profilesFileURL),
           let container = try? JSONDecoder().decode(SavedProfilesContainer.self, from: data) {
            var loadedProfiles = container.profiles
            for i in 0..<loadedProfiles.count {
                if let key = KeychainHelper.shared.read(key: loadedProfiles[i].keychainKey), !key.isEmpty {
                    loadedProfiles[i].apiKey = key
                } else if let legacyKey = KeychainHelper.shared.read(key: legacyKeychainApiKeyIdentifier), !legacyKey.isEmpty {
                    // 兼容旧版单一密钥迁移
                    loadedProfiles[i].apiKey = legacyKey
                    KeychainHelper.shared.save(key: loadedProfiles[i].keychainKey, secret: legacyKey)
                }
                
                // 智能纠偏：如果 modelName 被历史 default-model 覆盖，恢复为 name
                if loadedProfiles[i].modelName == "default-model" && !loadedProfiles[i].name.isEmpty && loadedProfiles[i].name != "默认模型" {
                    loadedProfiles[i].modelName = loadedProfiles[i].name
                }
            }
            if !loadedProfiles.isEmpty {
                let activeId = loadedProfiles.contains(where: { $0.id == container.activeProfileId })
                    ? container.activeProfileId
                    : loadedProfiles.first!.id
                return (loadedProfiles, activeId)
            }
        }
        
        // 2. 尝试无缝迁移旧版单一配置文件
        if let legacyData = try? Data(contentsOf: legacyConfigFileURL),
           let legacy = try? JSONDecoder().decode(AIModelConfig.self, from: legacyData) {
            let legacyKey = KeychainHelper.shared.read(key: legacyKeychainApiKeyIdentifier) ?? ""
            let migratedProfile = AIModelProfile(
                id: legacy.id,
                name: legacy.modelName.isEmpty ? "\(legacy.provider.rawValue)" : legacy.modelName,
                provider: legacy.provider,
                baseURL: legacy.baseURL,
                apiKey: legacyKey,
                modelName: legacy.modelName,
                temperature: legacy.temperature,
                maxTokens: legacy.maxTokens
            )
            save(profiles: [migratedProfile], activeId: migratedProfile.id)
            return ([migratedProfile], migratedProfile.id)
        }
        
        // 3. 初始全新安装：创建常用推荐预设
        let geminiDakka = AIModelProfile(
            id: UUID(),
            name: "中转站 (Gemini 3.1 Pro)",
            provider: .custom,
            baseURL: "https://grsai.dakka.com.cn/v1",
            apiKey: "",
            modelName: "gemini-3.1-pro",
            temperature: 0.3,
            maxTokens: 2048
        )
        let deepseek = AIModelProfile(
            id: UUID(),
            name: "DeepSeek 官方",
            provider: .deepseek,
            baseURL: "https://api.deepseek.com/v1",
            apiKey: "",
            modelName: "deepseek-chat",
            temperature: 0.3,
            maxTokens: 2048
        )
        let ollama = AIModelProfile(
            id: UUID(),
            name: "本地离线 (Ollama)",
            provider: .ollama,
            baseURL: "http://localhost:11434/v1",
            apiKey: "",
            modelName: "qwen2.5-coder",
            temperature: 0.3,
            maxTokens: 2048
        )
        
        let initialList = [geminiDakka, deepseek, ollama]
        save(profiles: initialList, activeId: geminiDakka.id)
        return (initialList, geminiDakka.id)
    }
    
    public static func save(profiles: [AIModelProfile], activeId: UUID) {
        // 1. 各预设独立加密写入 Keychain
        for p in profiles {
            if !p.apiKey.isEmpty {
                KeychainHelper.shared.save(key: p.keychainKey, secret: p.apiKey)
            } else {
                KeychainHelper.shared.delete(key: p.keychainKey)
            }
        }
        
        // 2. 剔除敏感密钥后存储 JSON
        let safeProfiles = profiles.map { p -> AIModelProfile in
            var clone = p
            clone.apiKey = ""
            return clone
        }
        let container = SavedProfilesContainer(activeProfileId: activeId, profiles: safeProfiles)
        if let data = try? JSONEncoder().encode(container) {
            try? data.write(to: profilesFileURL)
            ConfigManager.enforceSecurePermissions(at: profilesFileURL)
        }
    }
}

// MARK: - 向后兼容旧版引用
public struct AIModelConfig: Codable, Identifiable {
    public var id: UUID = UUID()
    public var provider: AIProviderType = .deepseek
    public var baseURL: String = AIProviderType.deepseek.defaultBaseURL
    public var apiKey: String = ""
    public var modelName: String = AIProviderType.deepseek.defaultModelName
    public var temperature: Double = 0.3
    public var maxTokens: Int = 2048
    
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
    
    public func save() {
        let profile = AIModelProfile(
            id: id,
            name: modelName,
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey,
            modelName: modelName,
            temperature: temperature,
            maxTokens: maxTokens
        )
        var (currentProfiles, _) = AIProfileStore.load()
        if let idx = currentProfiles.firstIndex(where: { $0.id == id }) {
            currentProfiles[idx] = profile
        } else {
            currentProfiles.append(profile)
        }
        AIProfileStore.save(profiles: currentProfiles, activeId: id)
    }
    
    public static func load() -> AIModelConfig {
        let (profiles, activeId) = AIProfileStore.load()
        if let current = profiles.first(where: { $0.id == activeId }) {
            return AIModelConfig(
                id: current.id,
                provider: current.provider,
                baseURL: current.baseURL,
                apiKey: current.apiKey,
                modelName: current.modelName,
                temperature: current.temperature,
                maxTokens: current.maxTokens
            )
        }
        return AIModelConfig()
    }
}
