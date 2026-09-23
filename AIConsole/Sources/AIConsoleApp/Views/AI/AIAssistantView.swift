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
            // Mode Selector Bar (Fast Fix / Commands Only / Deep Analysis)
            HStack(spacing: 4) {
                ForEach(AIDiagnoseMode.allCases) { mode in
                    let isSelected = (aiService.diagnoseMode == mode)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            aiService.diagnoseMode = mode
                        }
                        HapticFeedbackHelper.shared.performGeneric()
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                    .shadow(color: isSelected ? .black.opacity(0.1) : .clear, radius: 1, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(7)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            
            Divider()
            
            // Diagnostics Quick Actions Bar (Single-Node vs Multi-Node Cluster)
            HStack(spacing: 8) {
                let allNodes = allTerminalsGetter()
                if allNodes.count > 1 {
                    Menu {
                        Button(action: diagnoseAllClusterNodes) {
                            Label("🌐 联合诊断全部 \(allNodes.count) 台同网段设备", systemImage: "network")
                        }
                        Button(action: diagnoseActiveTerminal) {
                            Label("🖥️ 仅诊断当前单台设备", systemImage: "display")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stethoscope")
                            Text("联合诊断 (\(allNodes.count)台设备)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .disabled(aiService.isGenerating)
                    .help("一键抓取同网络所有已连接设备的输出，进行拓扑关联诊断")
                } else {
                    Button(action: diagnoseActiveTerminal) {
                        Label("提取终端上下文一键诊断", systemImage: "stethoscope")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(aiService.isGenerating)
                }
                
                if aiService.isGenerating {
                    Button(action: {
                        aiService.cancelCurrentGeneration()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                            Text("停止")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Spacer()
                
                Text(aiService.config.provider.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            
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
            
            // Input Bar
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    AIAutoGrowTextEditor(
                        text: $inputText,
                        placeholder: "输入运维诊断问题、报错排查或命令需求...",
                        onCommit: sendCurrentMessage
                    )
                    .frame(minHeight: 48, maxHeight: 120)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    
                    VStack(spacing: 4) {
                        if aiService.isGenerating {
                            Button(action: {
                                aiService.cancelCurrentGeneration()
                            }) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("停止当前生成")
                        } else {
                            Button(action: sendCurrentMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("发送提问 (Return)")
                        }
                    }
                    .padding(.bottom, 4)
                }
                
                HStack {
                    Text("提示: 按 Return 发送，按 Shift + Return 换行")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 320, idealWidth: 360)
    }
    
    private func diagnoseActiveTerminal() {
        let buffer = activeTerminalGetter()?.extractRecentBuffer(maxLines: 500) ?? ""
        aiService.send(
            userText: "请深度分析我当前终端的历史回滚日志与上下文，排查所有错误、异常与潜在隐患，并给出可行的修复命令和操作方案：",
            terminalContext: buffer
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
        
        aiService.send(
            userText: "我当前正在远程管理同一个局域网/业务集群下的多台协同设备。请结合以下各个节点的日志输出，从网络拓扑、上下游服务调用、链路通断与分布式依赖的角度进行联合关联诊断，定位导致异常的源头节点，并给出各节点的针对性修复方案：",
            terminalContext: combinedContext
        )
    }
    
    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        aiService.send(userText: text)
    }
}

struct ChatMessageRow: View {
    let message: ChatMessage
    let onExecuteCommand: (String) -> Void
    let onInsertCommand: (String) -> Void
    
    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
            HStack {
                if message.role == "user" { Spacer() }
                
                Text(message.role == "user" ? "我" : "AI Copilot")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if message.role != "user" { Spacer() }
            }
            
            HStack {
                if message.role == "user" { Spacer() }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(message.content.isEmpty && message.isStreaming ? "正在思考与组织诊断内容..." : message.content)
                            .font(.system(size: 13))
                            .foregroundColor(message.content.isEmpty && message.isStreaming ? .secondary : .primary)
                            .textSelection(.enabled)
                        
                        if message.isStreaming {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
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
                .background(message.role == "user" ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                if message.role != "user" { Spacer() }
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
