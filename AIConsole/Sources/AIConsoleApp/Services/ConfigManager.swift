import Foundation
import Combine

// MARK: - 主配置文件模型 (config.json)
public struct SecurityConfig: Codable, Equatable {
    public var enablePasswordProtection: Bool = false
    public var consentExpiryDays: Int = 30
    public var maxConsentAge: Int = 30
    public var enableRiskAssessment: Bool = true
    public var autoApproveLowRisk: Bool = true
    public var promptForMediumRisk: Bool = true
    public var requirePasswordForHighRisk: Bool = true
    public var dangerousPatterns: [String] = [
        "rm -rf /",
        "sudo rm -rf /",
        "format",
        "dd if=",
        "> /dev/null",
        "fork\\("
    ]
    public var allowedCommands: [String] = []
    public var forbiddenCommands: [String] = []
    
    public init() {}
}

public struct AIProviderItemConfig: Codable, Equatable {
    public var name: String = "openai-compatible"
    public var displayName: String = "OpenAI 兼容站点"
    public var enabled: Bool = true
    public var baseURL: String = "https://api.deepseek.com/v1"
    public var model: String = "deepseek-v4-flash"
    public var disableStreaming: Bool = false
    public var contextWindow: Int = 128000
    public var apiKey: String = ""
    
    public init() {}
}

public struct HotkeyConfig: Codable, Equatable {
    public var openChat: String = "Ctrl-Shift-A"
    public var generateCommand: String = "Ctrl-Shift-G"
    public var explainCommand: String = "Ctrl-Shift-E"
    
    public init() {}
}

public struct UIConfig: Codable, Equatable {
    public var showTooltips: Bool = true
    public var compactMode: Bool = false
    public var fontSize: Double = 14.0
    
    public init() {}
}

public struct ProxyConfig: Codable, Equatable {
    public var enabled: Bool = false
    public var httpProxy: String = ""
    public var httpsProxy: String = ""
    public var noProxy: [String] = ["localhost", "127.0.0.1", "::1", "*.local"]
    
    public init() {}
}

public struct AppMainConfig: Codable, Equatable {
    public var enabled: Bool = true
    public var defaultProvider: String = "openai-compatible"
    public var chatHistoryEnabled: Bool = true
    public var maxChatHistory: Int = 100
    public var autoSaveChat: Bool = true
    public var theme: String = "auto"
    public var language: String = "zh-CN"
    public var logLevel: String = "info"
    public var security: SecurityConfig = SecurityConfig()
    public var providers: [String: AIProviderItemConfig] = [
        "openai-compatible": AIProviderItemConfig()
    ]
    public var hotkeys: HotkeyConfig = HotkeyConfig()
    public var ui: UIConfig = UIConfig()
    public var agentMaxRounds: Int = 50
    public var proxy: ProxyConfig = ProxyConfig()
    
    public init() {}
}

// MARK: - 上下文配置文件模型 (context-config.json)
public struct ContextConfig: Codable, Equatable {
    public var maxContextTokens: Int = 128000
    public var reservedOutputTokens: Int = 16000
    public var compactThreshold: Double = 0.85
    public var pruneThreshold: Double = 0.70
    public var messagesToKeep: Int = 3
    public var bufferPercentage: Double = 0.1
    public var summaryPrompt: String = "请用一句话总结以下对话的要点，保留关键信息和用户意图："
    
    public init() {}
}

// MARK: - 集中式配置管理器 (ConfigManager)
public final class ConfigManager: ObservableObject {
    public static let shared = ConfigManager()
    
    @Published public var config: AppMainConfig = AppMainConfig()
    @Published public var contextConfig: ContextConfig = ContextConfig()
    
    // MARK: - 路径规范定义
    public static let projectFolderName = "AIConsole"
    
    /// 标准存储目录: ~/Library/Application Support/AIConsole/
    public static let standardDirectoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let projectDir = appSupport.appendingPathComponent(projectFolderName, isDirectory: true)
        return projectDir
    }()
    
    /// 标准配置文件路径
    public static var standardConfigFileURL: URL {
        standardDirectoryURL.appendingPathComponent("config.json")
    }
    
    /// 标准上下文策略文件路径
    public static var standardContextConfigFileURL: URL {
        standardDirectoryURL.appendingPathComponent("context-config.json")
    }
    
    /// 历史向后兼容旧路径 (~/config.json)
    public static var legacyConfigFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("config.json")
    }
    
    /// 历史向后兼容旧路径 (~/context-config.json)
    public static var legacyContextConfigFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("context-config.json")
    }
    
    private init() {
        migrateAndInitialize()
    }
    
    // MARK: - 平滑迁移与向后兼容 (Backwards Compatibility)
    public func migrateAndInitialize() {
        let fm = FileManager.default
        
        // 1. 递归创建规范目录 ~/Library/Application Support/AIConsole/
        if !fm.fileExists(atPath: Self.standardDirectoryURL.path) {
            do {
                try fm.createDirectory(at: Self.standardDirectoryURL, withIntermediateDirectories: true)
                print("[AIConsole Config] 创建标准配置目录: \(Self.standardDirectoryURL.path)")
            } catch {
                print("[AIConsole Config] ⚠️ 创建标准目录失败: \(error)")
            }
        }
        
        // 2. 检查并迁移 config.json
        migrateFile(
            legacyURL: Self.legacyConfigFileURL,
            targetURL: Self.standardConfigFileURL,
            fileName: "config.json"
        )
        
        // 3. 检查并迁移 context-config.json
        migrateFile(
            legacyURL: Self.legacyContextConfigFileURL,
            targetURL: Self.standardContextConfigFileURL,
            fileName: "context-config.json"
        )
        
        // 4. 读取配置
        loadConfigs()
    }
    
    private func migrateFile(legacyURL: URL, targetURL: URL, fileName: String) {
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: targetURL.path) && fm.fileExists(atPath: legacyURL.path) {
            do {
                try fm.moveItem(at: legacyURL, to: targetURL)
                Self.enforceSecurePermissions(at: targetURL)
                print("[AIConsole Config Migration] 🚀 平滑迁移完成: 已将旧路径 ~/\(fileName) 移动至标准路径 \(targetURL.path)，并设置 0600 安全权限。")
            } catch {
                print("[AIConsole Config Migration] ⚠️ 迁移 \(fileName) 出现异常: \(error)，尝试复制...")
                if (try? fm.copyItem(at: legacyURL, to: targetURL)) != nil {
                    try? fm.removeItem(at: legacyURL)
                    Self.enforceSecurePermissions(at: targetURL)
                    print("[AIConsole Config Migration] 🚀 复制并清理完成: \(fileName)")
                }
            }
        } else if fm.fileExists(atPath: targetURL.path) {
            // 如果新路径已存在，且旧路径也存在（多余污染），安全清理旧文件
            if fm.fileExists(atPath: legacyURL.path) {
                try? fm.removeItem(at: legacyURL)
                print("[AIConsole Config Migration] 🧹 已清理根目录下多余的旧配置文件: \(legacyURL.path)")
            }
            Self.enforceSecurePermissions(at: targetURL)
        }
    }
    
    // MARK: - 安全性与权限保护 (POSIX 0600)
    public static func enforceSecurePermissions(at url: URL) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            print("[AIConsole Config] ⚠️ 设置文件权限 0600 失败 (\(url.lastPathComponent)): \(error)")
        }
    }
    
    // MARK: - 配置读写
    public func loadConfigs() {
        let decoder = JSONDecoder()
        
        // 读取 config.json
        if let data = try? Data(contentsOf: Self.standardConfigFileURL),
           let parsed = try? decoder.decode(AppMainConfig.self, from: data) {
            self.config = parsed
        } else {
            // 初次默认生成并保存
            saveMainConfig()
        }
        
        // 读取 context-config.json
        if let data = try? Data(contentsOf: Self.standardContextConfigFileURL),
           let parsed = try? decoder.decode(ContextConfig.self, from: data) {
            self.contextConfig = parsed
        } else {
            saveContextConfig()
        }
    }
    
    public func saveMainConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(self.config)
            try data.write(to: Self.standardConfigFileURL, options: .atomic)
            Self.enforceSecurePermissions(at: Self.standardConfigFileURL)
        } catch {
            print("[AIConsole Config] ⚠️ 保存 config.json 失败: \(error)")
        }
    }
    
    public func saveContextConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(self.contextConfig)
            try data.write(to: Self.standardContextConfigFileURL, options: .atomic)
            Self.enforceSecurePermissions(at: Self.standardContextConfigFileURL)
        } catch {
            print("[AIConsole Config] ⚠️ 保存 context-config.json 失败: \(error)")
        }
    }
}
