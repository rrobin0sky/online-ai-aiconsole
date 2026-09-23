import Foundation
import Combine

public struct ChatMessage: Codable, Identifiable {
    public var id = UUID()
    public let role: String // "user", "assistant", "system"
    public var content: String
    public var commandCards: [AICommandCard]?
    public var isStreaming: Bool = false
    
    public init(id: UUID = UUID(), role: String, content: String, commandCards: [AICommandCard]? = nil, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.commandCards = commandCards
        self.isStreaming = isStreaming
    }
}

public enum AIDiagnoseMode: String, CaseIterable, Identifiable {
    case fast = "⚡ 极速修复"
    case commandsOnly = "💻 仅命令"
    case deep = "📖 深度分析"
    
    public var id: String { rawValue }
    
    public var systemPrompt: String {
        switch self {
        case .fast:
            return """
            你是一位极速高效的系统运维与网络工程师专家 (AI Console Copilot)。
            用户正在高压运维排障现场，【严禁任何废话、客套寒暄与开场白】。
            请一律按以下三段式标准 Markdown 卡片直接输出，字数严格控制在 150 字以内：

            ### 🎯 根因定位
            > [一句话指出核心故障根因，直接说人话，不超过2句]

            ### ⚡ 极速修复命令
            ```bash
            # 步骤 1: 排查或修复
            <执行命令>

            # 步骤 2: 验证效果
            <验证命令>
            ```

            ### ⚠️ 风险提示
            - [可选：仅当涉及数据删除、重启或重大网络中断时提醒，限1点；无则省略]
            """
        case .commandsOnly:
            return """
            你是一位纯命令生成助手。
            【严禁输出任何分析、任何废话、任何开场白或解释】。
            你只允许输出一个完整的 ```bash 代码块，里面包含可以直接在终端按顺序执行的命令。
            每条命令上方允许写一行极短的 # 注释。
            """
        case .deep:
            return """
            你是一位资深系统与网络架构诊断专家。
            请对终端报错与集群拓扑进行系统化、深度的根因剖析，提供：
            1. 故障全链路定界与根本原因剖析；
            2. 详细的分步排查与修复方案（命令放在 ```bash 代码块中）；
            3. 长效防范机制与配置调优建议。
            """
        }
    }
}

@MainActor
public final class AIService: ObservableObject {
    @Published public var config: AIModelConfig = AIModelConfig()
    @Published public var messages: [ChatMessage] = []
    @Published public var isGenerating: Bool = false
    @Published public var errorMessage: String?
    @Published public var diagnoseMode: AIDiagnoseMode = .fast
    
    private var activeTask: Task<Void, Never>?
    
    public init() {
        self.config = AIModelConfig.load()
        self.messages.append(ChatMessage(
            role: "assistant",
            content: "你好！我是你的 AI 终端与网络运维助手。当终端遇到报错、日志排查或需要生成运维命令时，随时可以问我。\n已默认启用【⚡ 极速修复】模式（一句话根因 + 直接给修复命令）。所有敏感凭据已自动脱敏保护。"
        ))
    }
    
    public func saveConfig() {
        config.save()
    }
    
    public func testConnection(candidateConfig: AIModelConfig) async -> (success: Bool, message: String) {
        let endpoint = candidateConfig.baseURL.hasSuffix("/") ? "\(candidateConfig.baseURL)chat/completions" : "\(candidateConfig.baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            return (false, "Base URL 格式错误")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !candidateConfig.apiKey.isEmpty {
            request.setValue("Bearer \(candidateConfig.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10
        
        let bodyObj: [String: Any] = [
            "model": candidateConfig.modelName,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 5
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyObj) else {
            return (false, "序列化请求失败")
        }
        request.httpBody = httpBody
        
        let startTime = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "服务响应非 HTTP 协议")
            }
            
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            if httpResponse.statusCode == 200 {
                return (true, "连接成功 (延时 \(elapsed)ms)")
            } else {
                return (false, "HTTP \(httpResponse.statusCode) 错误，请检查 API Key 或模型名称")
            }
        } catch {
            return (false, "连接失败: \(error.localizedDescription)")
        }
    }
    
    public func cancelCurrentGeneration() {
        activeTask?.cancel()
        activeTask = nil
        isGenerating = false
        if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" && messages[lastIdx].isStreaming {
            messages[lastIdx].isStreaming = false
            messages[lastIdx].commandCards = parseCommandCards(from: messages[lastIdx].content)
        }
    }
    
    public func clearMessagesAndStartNewSession() {
        cancelCurrentGeneration()
        messages.removeAll()
        messages.append(ChatMessage(
            role: "assistant",
            content: "已开启全新的 AI 诊断会话（已清除全部历史上下文）。请随时提出新的运维问题或提取终端报错！"
        ))
        errorMessage = nil
    }
    
    /// Log Distillation: Extract error-rich lines to avoid bloated prompt tokens and unfocused responses
    private func distillLogs(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        guard lines.count > 40 else { return raw }
        
        let keywords = ["error", "fatal", "exception", "failed", "failure", "panic", "denied", "refused", "timeout", "critical", "warning", "errno"]
        var importantIndices = Set<Int>()
        
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            if keywords.contains(where: { lower.contains($0) }) {
                // Include 2 lines before and 2 lines after
                for offset in -2...2 {
                    let idx = i + offset
                    if idx >= 0 && idx < lines.count {
                        importantIndices.insert(idx)
                    }
                }
            }
        }
        
        // If not enough error lines detected, take the last 40 lines
        if importantIndices.count < 5 {
            return lines.suffix(40).joined(separator: "\n")
        }
        
        var distilled: [String] = []
        var lastIdx = -1
        for idx in importantIndices.sorted() {
            if lastIdx != -1 && idx > lastIdx + 1 {
                distilled.append("... [省略 \(idx - lastIdx - 1) 行正常日志] ...")
            }
            distilled.append(lines[idx])
            lastIdx = idx
        }
        return distilled.joined(separator: "\n")
    }
    
    public func send(userText: String, terminalContext: String? = nil) {
        guard !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var promptText = userText
        if let context = terminalContext, !context.isEmpty {
            // 1. Security Redaction
            let redacted = DataRedactor.shared.redact(context)
            // 2. Intelligent Log Distillation
            let distilled = distillLogs(redacted)
            promptText += "\n\n【终端报错上下文 (智能提纯)】:\n```\n\(distilled)\n```"
        }
        
        let userMsg = ChatMessage(role: "user", content: promptText)
        messages.append(userMsg)
        isGenerating = true
        errorMessage = nil
        
        // Append a placeholder assistant message for streaming
        let assistantMsgId = UUID()
        let assistantMsg = ChatMessage(id: assistantMsgId, role: "assistant", content: "", commandCards: nil, isStreaming: true)
        messages.append(assistantMsg)
        
        activeTask = Task {
            do {
                try await performStreamingChatRequest(messageId: assistantMsgId)
            } catch {
                if Task.isCancelled {
                    // Canceled by user, keep what was generated
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.messages[idx].isStreaming = false
                        self.messages[idx].commandCards = self.parseCommandCards(from: self.messages[idx].content)
                    }
                } else {
                    self.errorMessage = error.localizedDescription
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        if self.messages[idx].content.isEmpty {
                            self.messages[idx].content = "⚠️ 请求失败: \(error.localizedDescription)\n请在设置中检查 API Key 与 Base URL。"
                        } else {
                            self.messages[idx].content += "\n\n⚠️ [流式传输中断: \(error.localizedDescription)]"
                        }
                        self.messages[idx].isStreaming = false
                    }
                }
            }
            self.isGenerating = false
            self.activeTask = nil
        }
    }
    
    private func performStreamingChatRequest(messageId: UUID) async throws {
        let endpoint = config.baseURL.hasSuffix("/") ? "\(config.baseURL)chat/completions" : "\(config.baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 60
        
        var payloadMessages: [[String: String]] = [
            ["role": "system", "content": diagnoseMode.systemPrompt]
        ]
        // Include recent history excluding streaming placeholder
        let history = messages.filter { $0.id != messageId }.suffix(6)
        for m in history {
            payloadMessages.append(["role": m.role, "content": m.content])
        }
        
        let bodyObj: [String: Any] = [
            "model": config.modelName,
            "messages": payloadMessages,
            "temperature": config.temperature,
            "max_tokens": config.maxTokens,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyObj)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API 状态码异常 (\(httpResponse.statusCode))"])
        }
        
        var accumulatedText = ""
        
        for try await line in bytes.lines {
            try Task.checkCancellation()
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            
            let dataPayload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if dataPayload == "[DONE]" {
                break
            }
            
            guard let jsonData = dataPayload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first else {
                continue
            }
            
            var deltaContent: String?
            if let delta = firstChoice["delta"] as? [String: Any], let content = delta["content"] as? String {
                deltaContent = content
            } else if let text = firstChoice["text"] as? String {
                deltaContent = text
            }
            
            if let chunk = deltaContent, !chunk.isEmpty {
                accumulatedText += chunk
                if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
                    self.messages[idx].content = accumulatedText
                    // Dynamically parse command cards
                    self.messages[idx].commandCards = self.parseCommandCards(from: accumulatedText)
                }
            }
        }
        
        if let idx = self.messages.firstIndex(where: { $0.id == messageId }) {
            self.messages[idx].isStreaming = false
            self.messages[idx].commandCards = self.parseCommandCards(from: accumulatedText)
        }
    }
    
    public func parseCommandCards(from text: String) -> [AICommandCard] {
        var cards: [AICommandCard] = []
        let pattern = "```(?:bash|sh|cisco|shell)?\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return cards }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let codeRange = match.range(at: 1)
            let rawCode = nsString.substring(with: codeRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !rawCode.isEmpty {
                let lines = rawCode.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && !$0.isEmpty }
                let commandToExec = lines.joined(separator: "\n")
                
                let risk = evaluateRisk(command: commandToExec)
                cards.append(AICommandCard(command: commandToExec, explanation: "AI 推荐执行的操作命令", riskLevel: risk))
            }
        }
        return cards
    }
    
    public func evaluateRisk(command: String) -> CommandRiskLevel {
        let lower = command.lowercased()
        if lower.contains("rm -rf /") || lower.contains("mkfs") || lower.contains("dd if=") || lower.contains("reboot") || lower.contains("shutdown") || lower.contains("chmod 777 -r /") || lower.contains("erase startup-config") || lower.contains("reload") {
            return .dangerous
        }
        if lower.contains("rm ") || lower.contains("kill -9") || lower.contains("systemctl restart") || lower.contains("chmod ") || lower.contains("chown ") || lower.contains("iptables -f") || lower.contains("no ip") || lower.contains("undo ") {
            return .caution
        }
        return .safe
    }
}
