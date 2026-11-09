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
            // Unified Diagnostic & Mode Bar (Compact Pro Style)
            VStack(spacing: 6) {
                // Row 1: 环境上下文栏 (当前会话 + 当前模型)
                HStack(spacing: 6) {
                    // 当前会话切换
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
                                .truncationMode(.tail)
                                .frame(maxWidth: 130, alignment: .leading)
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
                    
                    Spacer(minLength: 4)
                    
                    // 🌟 快捷大模型切换下拉胶囊 (Quick Model Switcher)
                    Menu {
                        Section("切换模型预设") {
                            ForEach(aiService.profiles) { p in
                                Button(action: {
                                    aiService.selectProfile(id: p.id)
                                    HapticFeedbackHelper.shared.performGeneric()
                                }) {
                                    HStack {
                                        Text(p.name.isEmpty ? p.modelName : p.name)
                                        if p.id == aiService.activeProfileId {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            NotificationCenter.default.post(name: .AIConsoleOpenSettings, object: nil)
                        }) {
                            Label("管理模型预设...", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                                .foregroundColor(.purple)
                            Text(aiService.currentProfile.name.isEmpty ? aiService.currentProfile.modelName : aiService.currentProfile.name)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 120, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                }
                
                // Row 2: 诊断模式选择与核心操作栏
                HStack(spacing: 6) {
                    // 诊断模式分段胶囊
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
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                            .shadow(color: isSelected ? Color.black.opacity(0.08) : Color.clear, radius: 1, y: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(5)
                    
                    Spacer(minLength: 4)
                    
                    // 诊断动作按钮 (保证单行、不折行、紧凑优雅)
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
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("诊断集群 (\(allNodes.count))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.accentColor)
                            .cornerRadius(5)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(aiService.isGenerating)
                    } else {
                        Button(action: {
                            HapticFeedbackHelper.shared.performGeneric()
                            diagnoseActiveTerminal()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("一键诊断")
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.accentColor)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .disabled(aiService.isGenerating)
                    }
                    
                    if aiService.isGenerating {
                        Button(action: {
                            HapticFeedbackHelper.shared.performAlignment()
                            aiService.cancelCurrentGeneration()
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 7))
                                Text("停止")
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3.5)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 8)
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
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 320, idealWidth: 360)
    }
    
    private func diagnoseActiveTerminal() {
        let term = activeTerminalGetter()
        let buffer = term?.extractRecentBuffer(maxLines: 2000) ?? ""
        term?.markBufferAsSynced()
        aiService.send(
            userText: "请深度分析我当前终端的历史回滚日志与上下文，排查所有错误、异常与潜在隐患，并给出可行的修复命令和操作方案：",
            terminalContext: buffer,
            isIncremental: false,
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
            isIncremental: false,
            targetSessionId: AIService.clusterSessionId
        )
    }
    
    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        
        // Auto-capture incremental new terminal output seamlessly in background
        if let term = activeTerminalGetter() {
            let (newOutput, isIncremental) = term.extractIncrementalOrRecentBuffer(maxLines: 1500)
            if !newOutput.isEmpty {
                aiService.send(
                    userText: text,
                    terminalContext: newOutput,
                    isIncremental: isIncremental,
                    targetSessionId: aiService.activeSessionId
                )
                return
            }
        }
        
        aiService.send(userText: text, targetSessionId: aiService.activeSessionId)
    }
}

struct ChatMessageRow: View {
    let message: ChatMessage
    let onExecuteCommand: (String) -> Void
    let onInsertCommand: (String) -> Void
    
    private var parsedContent: (userText: String, attachedContext: String?) {
        guard message.role == "user" else {
            return (message.content, nil)
        }
        let separators = [
            "\n\n【用户最新执行的终端命令与产生的新输出】:\n",
            "\n\n【终端上下文 (智能提纯)】:\n",
            "\n\n【终端报错上下文 (智能提纯)】:\n"
        ]
        for sep in separators {
            if let range = message.content.range(of: sep) {
                let userPart = String(message.content[..<range.lowerBound])
                let contextPart = String(message.content[range.upperBound...])
                return (userPart, contextPart)
            }
        }
        return (message.content, nil)
    }
    
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
                if message.role == "user" { Spacer(minLength: 30) }
                
                let parsed = parsedContent
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(parsed.userText.isEmpty && message.isStreaming ? "正在分析终端上下文并生成方案..." : parsed.userText)
                            .font(.system(size: 12.5))
                            .lineSpacing(3)
                            .foregroundColor(parsed.userText.isEmpty && message.isStreaming ? .secondary : .primary)
                            .textSelection(.enabled)
                        
                        if message.isStreaming {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .opacity(0.8)
                        }
                    }
                    
                    // Compact Attached Terminal Context preview for user messages
                    if let ctx = parsed.attachedContext, !ctx.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 8))
                                Text("附带终端实时执行输出:")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.secondary.opacity(0.9))
                            
                            Text(ctx.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .padding(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(4)
                        }
                        .padding(.top, 2)
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
    
    @State private var profiles: [AIModelProfile] = []
    @State private var selectedId: UUID
    @State private var activeId: UUID
    @State private var showApiKeyPlain: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: (success: Bool, message: String)?
    
    init(aiService: AIService) {
        self.aiService = aiService
        let list = aiService.profiles.isEmpty ? [AIModelProfile()] : aiService.profiles
        let currentActive = aiService.activeProfileId
        _profiles = State(initialValue: list)
        _selectedId = State(initialValue: currentActive)
        _activeId = State(initialValue: currentActive)
    }
    
    private var currentBinding: Binding<AIModelProfile> {
        Binding(
            get: {
                if let p = profiles.first(where: { $0.id == selectedId }) {
                    return p
                }
                return profiles.first ?? AIModelProfile()
            },
            set: { updated in
                if let idx = profiles.firstIndex(where: { $0.id == updated.id }) {
                    profiles[idx] = updated
                }
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("模型配置")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Master-Detail
            HSplitView {
                // Left
                VStack(spacing: 0) {
                    List(selection: $selectedId) {
                        ForEach(profiles) { p in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(p.id == activeId ? Color.green : Color.clear)
                                    .frame(width: 6, height: 6)
                                    .overlay(
                                        Circle().stroke(Color.secondary.opacity(0.3), lineWidth: p.id == activeId ? 0 : 1)
                                    )
                                
                                Text(p.name.isEmpty ? p.modelName : p.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .tag(p.id)
                        }
                    }
                    .listStyle(.sidebar)
                    
                    Divider()
                    
                    HStack(spacing: 4) {
                        Button(action: addProfile) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: deleteSelected) {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(profiles.count <= 1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                }
                .frame(width: 160)
                
                // Right Form
                Form {
                    TextField("预设名称", text: currentBinding.name)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("服务商", selection: currentBinding.provider) {
                        ForEach(AIProviderType.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .onChange(of: currentBinding.wrappedValue.provider) { _, newP in
                        if currentBinding.wrappedValue.baseURL.isEmpty {
                            currentBinding.wrappedValue.baseURL = newP.defaultBaseURL
                        }
                        if currentBinding.wrappedValue.modelName.isEmpty {
                            currentBinding.wrappedValue.modelName = newP.defaultModelName
                        }
                    }
                    
                    TextField("Base URL", text: currentBinding.baseURL)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        if showApiKeyPlain {
                            TextField("API Key", text: currentBinding.apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: currentBinding.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: { showApiKeyPlain.toggle() }) {
                            Image(systemName: showApiKeyPlain ? "eye.slash" : "eye")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    TextField("模型", text: currentBinding.modelName)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack(spacing: 12) {
                        Button(action: runTest) {
                            HStack(spacing: 4) {
                                if isTesting {
                                    ProgressView().scaleEffect(0.6)
                                }
                                Text("测试连接")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTesting || currentBinding.wrappedValue.baseURL.isEmpty)
                        
                        if let res = testResult {
                            HStack(spacing: 4) {
                                Image(systemName: res.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(res.success ? .green : .red)
                                Text(res.message)
                                    .font(.caption)
                                    .foregroundColor(res.success ? .green : .red)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        if currentBinding.wrappedValue.id == activeId {
                            Text("默认使用中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Button("设为默认") {
                                activeId = currentBinding.wrappedValue.id
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
                .formStyle(.grouped)
                .padding(.horizontal, 8)
            }
            .frame(height: 300)
            
            Divider()
            
            // Bottom Bar
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("保存") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520, height: 380)
    }
    
    private func addProfile() {
        let p = AIModelProfile(
            id: UUID(),
            name: "新配置",
            provider: .custom,
            baseURL: "https://grsai.dakka.com.cn/v1",
            apiKey: "",
            modelName: "gemini-3.1-pro"
        )
        profiles.append(p)
        selectedId = p.id
    }
    
    private func deleteSelected() {
        guard profiles.count > 1 else { return }
        profiles.removeAll(where: { $0.id == selectedId })
        if activeId == selectedId {
            activeId = profiles.first!.id
        }
        selectedId = profiles.first!.id
    }
    
    private func runTest() {
        isTesting = true
        testResult = nil
        let target = currentBinding.wrappedValue
        Task {
            let res = await aiService.testConnection(profile: target)
            self.testResult = res
            self.isTesting = false
        }
    }
    
    private func save() {
        for i in 0..<profiles.count {
            profiles[i].baseURL = profiles[i].baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            profiles[i].apiKey = profiles[i].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            profiles[i].modelName = profiles[i].modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if profiles[i].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profiles[i].name = profiles[i].modelName.isEmpty ? "未命名" : profiles[i].modelName
            }
        }
        aiService.profiles = profiles
        aiService.activeProfileId = activeId
        aiService.saveProfiles()
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
