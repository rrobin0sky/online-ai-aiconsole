import SwiftUI

public struct AIAssistantView: View {
    @ObservedObject var aiService: AIService
    let activeTerminalGetter: () -> CustomTerminalView?
    let allTerminalsGetter: () -> [(title: String, host: String, buffer: String)]
    let onExecuteCommand: (String) -> Void
    let onInsertCommand: (String) -> Void
    
    @State private var inputText: String = ""
    @State private var showSettings: Bool = false
    
    public init(
        aiService: AIService,
        activeTerminalGetter: @escaping () -> CustomTerminalView?,
        allTerminalsGetter: @escaping () -> [(title: String, host: String, buffer: String)] = { [] },
        onExecuteCommand: @escaping (String) -> Void,
        onInsertCommand: @escaping (String) -> Void
    ) {
        self.aiService = aiService
        self.activeTerminalGetter = activeTerminalGetter
        self.allTerminalsGetter = allTerminalsGetter
        self.onExecuteCommand = onExecuteCommand
        self.onInsertCommand = onInsertCommand
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Unified Diagnostic & Mode Bar
            VStack(spacing: 6) {
                // Session Scope Indicator & Selector
                HStack(spacing: 6) {
                    Menu {
                        Button(action: {
                            aiService.activeSessionId = AIService.clusterSessionId
                        }) {
                            Label("🌐 全局集群联合工作区", systemImage: "network")
                        }
                        
                        Divider()
                        
                        ForEach(Array(aiService.sessions.values)) { sess in
                            if sess.id != AIService.clusterSessionId {
                                Button(action: {
                                    aiService.activeSessionId = sess.id
                                }) {
                                    HStack {
                                        Label(sess.title, systemImage: "terminal")
                                        if sess.isGenerating {
                                            Text("(生成中...)")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: aiService.activeSessionId == AIService.clusterSessionId ? "network" : "terminal")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(aiService.currentSessionTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(5)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    Spacer()
                    
                    // Provider badge
                    Text(aiService.config.provider.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(4)
                }
                
                HStack(spacing: 6) {
                    // Mode selector segmented buttons
                    HStack(spacing: 2) {
                        ForEach(AIDiagnoseMode.allCases) { mode in
                            let isSelected = (aiService.diagnoseMode == mode)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    aiService.diagnoseMode = mode
                                }
                                HapticFeedbackHelper.shared.performGeneric()
                            }) {
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                            .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    if aiService.isGenerating {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.5)
                            Text("分析中...")
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                        }
                    }
                }
                
                // One-click diagnosis button
                HStack(spacing: 8) {
                    let allNodes = allTerminalsGetter()
                    if allNodes.count > 1 {
                        Menu {
                            Button(action: diagnoseAllClusterNodes) {
                                Label("联合诊断全部 \(allNodes.count) 台节点", systemImage: "network")
                            }
                            Button(action: diagnoseActiveTerminal) {
                                Label("仅诊断当前单台节点", systemImage: "display")
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                Text("联合诊断集群 (\(allNodes.count)台)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                        .disabled(aiService.isGenerating)
                    } else {
                        Button(action: diagnoseActiveTerminal) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                Text("提取终端上下文一键诊断")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color.accentColor)
                        .disabled(aiService.isGenerating)
                    }
                    
                    if aiService.isGenerating {
                        Button(action: {
                            aiService.cancelCurrentGeneration()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 9))
                                Text("停止")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Chat Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(aiService.messages) { msg in
                            ChatMessageRow(
                                message: msg,
                                onExecuteCommand: onExecuteCommand,
                                onInsertCommand: onInsertCommand
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .background(Color.clear)
                .onChange(of: aiService.messages.last?.content) { _, _ in
                    if let last = aiService.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: aiService.messages.count) { _, _ in
                    if let last = aiService.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Refined Native Input Bar
            HStack(alignment: .bottom, spacing: 8) {
                AIAutoGrowTextEditor(
                    text: $inputText,
                    placeholder: "向 AI 提问或寻求命令诊断... (Return 发送)",
                    onCommit: sendCurrentMessage
                )
                .frame(minHeight: 40, maxHeight: 120)
                .padding(6)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                )
                
                VStack(spacing: 4) {
                    if aiService.isGenerating {
                        Button(action: {
                            aiService.cancelCurrentGeneration()
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("停止当前生成")
                    } else {
                        Button(action: sendCurrentMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.4) : .accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("发送提问 (Return)")
                    }
                }
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 320, idealWidth: 360)
    }
    
    private func diagnoseActiveTerminal() {
        let buffer = activeTerminalGetter()?.extractRecentBuffer(maxLines: 500) ?? ""
        aiService.send(
            userText: "请深度分析我当前终端的历史回滚日志与上下文，排查所有错误、异常与潜在隐患，并给出可行的修复命令和操作方案：",
            terminalContext: buffer,
            targetSessionId: aiService.activeSessionId
        )
    }
    
    private func diagnoseAllClusterNodes() {
        let nodes = allTerminalsGetter()
        guard !nodes.isEmpty else {
            diagnoseActiveTerminal()
            return
        }
        
        var combinedContext = "【同网段多设备联合拓扑日志 (共 \(nodes.count) 个活跃节点)】:\n"
        for (idx, node) in nodes.enumerated() {
            combinedContext += "\n=== [节点 \(idx + 1)] 设备: \(node.title) (Host: \(node.host)) ===\n"
            combinedContext += node.buffer.isEmpty ? "(无新输出或输出为空)" : node.buffer
            combinedContext += "\n"
        }
        
        aiService.selectSession(tabId: AIService.clusterSessionId, title: "🌐 全局集群联合工作区")
        aiService.send(
            userText: "我当前正在远程管理同一个局域网/业务集群下的多台协同设备。请结合以下各个节点的日志输出，从网络拓扑、上下游服务调用、链路通断与分布式依赖的角度进行联合关联诊断，定位导致异常的源头节点，并给出各节点的针对性修复方案：",
            terminalContext: combinedContext,
            targetSessionId: AIService.clusterSessionId
        )
    }
    
    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        aiService.send(userText: text, targetSessionId: aiService.activeSessionId)
    }
}

struct ChatMessageRow: View {
    let message: ChatMessage
    let onExecuteCommand: (String) -> Void
    let onInsertCommand: (String) -> Void
    
    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 5) {
            // Header with subtle icon
            HStack(spacing: 5) {
                if message.role == "user" {
                    Spacer()
                    Text("我")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.purple)
                    Text("AI 运维助手")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            HStack {
                if message.role == "user" { Spacer(minLength: 40) }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(message.content.isEmpty && message.isStreaming ? "正在分析终端上下文并生成方案..." : message.content)
                            .font(.system(size: 12.5))
                            .lineSpacing(3)
                            .foregroundColor(message.content.isEmpty && message.isStreaming ? .secondary : .primary)
                            .textSelection(.enabled)
                        
                        if message.isStreaming {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .opacity(0.8)
                        }
                    }
                    
                    // Render safe command cards
                    if let cards = message.commandCards, !cards.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(cards) { card in
                                AICommandCardView(
                                    card: card,
                                    onExecute: onExecuteCommand,
                                    onInsert: onInsertCommand
                                )
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(message.role == "user" ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(message.role == "user" ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 0.5)
                )
                
                if message.role != "user" { Spacer(minLength: 20) }
            }
        }
    }
}

struct AIModelSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var aiService: AIService
    
    @State private var selectedProvider: AIProviderType
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var modelName: String
    @State private var showApiKeyPlain: Bool = false
    
    @State private var isTesting: Bool = false
    @State private var testResult: (success: Bool, message: String)?
    @State private var showSavedAlert: Bool = false
    
    init(aiService: AIService) {
        self.aiService = aiService
        _selectedProvider = State(initialValue: aiService.config.provider)
        _baseURL = State(initialValue: aiService.config.baseURL)
        _apiKey = State(initialValue: aiService.config.apiKey)
        _modelName = State(initialValue: aiService.config.modelName)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sheet Header
            HStack {
                Label("AI 模型与 API 配置", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Form content
            Form {
                Section("服务商与模型选择") {
                    Picker("模型服务商", selection: $selectedProvider) {
                        ForEach(AIProviderType.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .onChange(of: selectedProvider) { _, newProvider in
                        baseURL = newProvider.defaultBaseURL
                        modelName = newProvider.defaultModelName
                    }
                    
                    TextField("模型名称 (Model)", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("接口地址与认证密钥 (Keychain 加密保护)") {
                    TextField("API Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("API Key (密钥)")
                            Spacer()
                            Button(action: { showApiKeyPlain.toggle() }) {
                                Image(systemName: showApiKeyPlain ? "eye.slash" : "eye")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if showApiKeyPlain {
                            TextField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                
                Section("连通性验证") {
                    HStack(spacing: 12) {
                        Button(action: runConnectionTest) {
                            HStack(spacing: 4) {
                                if isTesting {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text("测试 API 连通性")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTesting || baseURL.isEmpty)
                        
                        if let res = testResult {
                            HStack(spacing: 4) {
                                Image(systemName: res.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(res.success ? .green : .red)
                                Text(res.message)
                                    .font(.caption)
                                    .foregroundColor(res.success ? .green : .red)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)
            
            Divider()
            
            // Bottom Action Bar
            HStack {
                Text("🔒 API Key 将自动存入系统 Keychain，BaseURL/模型参数自动保存至本地。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                
                Button("保存并应用") {
                    saveAndApply()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 460)
        .onAppear {
            // Re-sync with latest stored config
            self.selectedProvider = aiService.config.provider
            self.baseURL = aiService.config.baseURL
            self.apiKey = aiService.config.apiKey
            self.modelName = aiService.config.modelName
        }
    }
    
    private func runConnectionTest() {
        isTesting = true
        testResult = nil
        let candidate = AIModelConfig(
            provider: selectedProvider,
            baseURL: baseURL,
            apiKey: apiKey,
            modelName: modelName
        )
        Task {
            let res = await aiService.testConnection(candidateConfig: candidate)
            self.testResult = res
            self.isTesting = false
        }
    }
    
    private func saveAndApply() {
        var updated = aiService.config
        updated.provider = selectedProvider
        updated.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        aiService.config = updated
        aiService.saveConfig()
    }
}

// MARK: - Custom NSTextView with Return=Send and Shift+Return=Newline
struct AIAutoGrowTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        
        context.coordinator.textView = textView
        context.coordinator.onCommit = onCommit
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.onCommit = onCommit
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onCommit: () -> Void
        weak var textView: NSTextView?
        
        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self._text = text
            self.onCommit = onCommit
        }
        
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            self.text = tv.string
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                let isShiftOrOption = event?.modifierFlags.contains(.shift) == true ||
                                      event?.modifierFlags.contains(.option) == true ||
                                      event?.modifierFlags.contains(.control) == true
                
                if isShiftOrOption {
                    // Shift + Enter or Option + Enter -> Newline
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    // Enter alone -> Send
                    onCommit()
                    return true
                }
            }
            return false
        }
    }
}
