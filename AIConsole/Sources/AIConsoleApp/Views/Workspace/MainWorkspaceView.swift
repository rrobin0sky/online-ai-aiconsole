import SwiftUI

public enum RightPanelTab: String, CaseIterable, Identifiable {
    case ai = "AI 运维助手"
    case snippets = "常用运维命令"
    
    public var id: String { rawValue }
    public var iconName: String {
        switch self {
        case .ai: return "sparkles"
        case .snippets: return "command.square.fill"
        }
    }
}

public struct MainWorkspaceView: View {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var aiService = AIService()
    @StateObject private var historyStore = HistoryStore.shared
    @StateObject private var snippetStore = SnippetStore.shared
    @StateObject private var auditStore = AuditStore.shared
    @StateObject private var themeStore = ThemeStore.shared
    
    @State private var tabs: [WorkspaceTab] = []
    @State private var activeTabId: UUID?
    
    // Cache active terminal views per tab to preserve focus and lifecycle
    @State private var terminalViews: [UUID: CustomTerminalView] = [:]
    
    @State private var showRightPanel: Bool = false
    @State private var activeRightTab: RightPanelTab = .ai
    @State private var isMultiExecEnabled: Bool = false
    @State private var broadcastCommandText: String = ""
    @State private var enableLiveKeyboardMirroring: Bool = true
    @State private var broadcastTargetTabIds: Set<UUID> = []
    @State private var broadcastFeedback: String? = nil
    
    @State private var showSettingsSheet: Bool = false
    @State private var showNewSessionSheet: Bool = false
    @State private var showNewGroupSheet: Bool = false
    @State private var showQuickPalette: Bool = false
    
    // Auto-update uptime timer for active sessions
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    private var broadcastEligibleTabs: [WorkspaceTab] {
        tabs.filter { $0.session.protocolType.isTerminalSupported }
    }
    
    private var activeTab: WorkspaceTab? {
        tabs.first(where: { $0.id == activeTabId })
    }
    
    private var activeTerminal: CustomTerminalView? {
        if let id = activeTabId, let term = terminalViews[id] {
            return term
        }
        if let firstTerm = terminalViews.values.first {
            return firstTerm
        }
        return nil
    }
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(
                sessionStore: sessionStore,
                onOpenSession: { session in
                    openSessionInTab(session, forceNew: true)
                },
                onOpenAllInGroup: { group in
                    if let children = group.children {
                        for child in children where !child.isGroup {
                            openSessionInTab(child, forceNew: true)
                        }
                    }
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Top Native-Styled Tab Bar with Reordering & Quick Actions
                    TabBarView(
                        tabs: $tabs,
                        activeTabId: activeTabId,
                        onSelectTab: { tab in
                            HapticFeedbackHelper.shared.performGeneric()
                            switchToTab(tab.id)
                        },
                        onCloseTab: { tab in
                            closeTab(tab)
                        },
                        onNewTab: {
                            openDefaultSession(forceNew: true)
                        },
                        onOpenPalette: {
                            withAnimation(.spring()) {
                                showQuickPalette.toggle()
                            }
                        }
                    )
                    
                    Divider()
                    
                    // Main Terminal Canvas with Floating Broadcast HUD
                    ZStack(alignment: .top) {
                        // Canvas Area
                        ZStack {
                            if tabs.isEmpty {
                                EmptyStateView(
                                    onLaunchLocalTerminal: {
                                        launchLocalTerminal()
                                    },
                                    onNewSession: {
                                        showNewSessionSheet = true
                                    }
                                )
                            } else {
                                ForEach(tabs) { tab in
                                    let isCurrent = (tab.id == activeTabId)
                                    Group {
                                        switch tab.session.protocolType {
                                        case .ssh, .telnet, .serial, .ble, .local:
                                            TerminalSplitView(
                                                session: tab.session,
                                                onDirectoryChanged: { newDir in
                                                    updateTabDirectory(tabId: tab.id, directory: newDir)
                                                },
                                                onTerminalReady: { termView in
                                                    self.terminalViews[tab.id] = termView
                                                    if self.activeTabId == tab.id {
                                                        focusTerminal(termView)
                                                    }
                                                },
                                                onDiagnoseRequested: { contextSnippet in
                                                    HapticFeedbackHelper.shared.performAlignment()
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        showRightPanel = true
                                                        activeRightTab = .ai
                                                    }
                                                    aiService.send(
                                                        userText: "检测到终端产生报错，请针对以下报错信息进行快速根因分析，并给出修复命令：",
                                                        terminalContext: contextSnippet
                                                    )
                                                }
                                            )
                                        case .vnc:
                                            VNCView(session: tab.session)
                                        case .sftp, .scp, .ftp:
                                            FTPBrowserView(session: tab.session)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .opacity(isCurrent ? 1 : 0)
                                    .allowsHitTesting(isCurrent)
                                    .zIndex(isCurrent ? 1 : 0)
                                }
                            }
                        }
                        
                        // Floating Glass HUD Broadcast Center (macOS Dynamic Island Style)
                        if isMultiExecEnabled {
                            FloatingBroadcastHUDView(
                                tabs: broadcastEligibleTabs,
                                targetIds: $broadcastTargetTabIds,
                                enableMirroring: $enableLiveKeyboardMirroring,
                                commandText: $broadcastCommandText,
                                feedbackText: broadcastFeedback,
                                onExecute: { cmd in
                                    executeBroadcast(command: cmd, autoExecute: true)
                                },
                                onInsert: { cmd in
                                    executeBroadcast(command: cmd, autoExecute: false)
                                },
                                onSendCtrlC: {
                                    sendBroadcastCtrlC()
                                },
                                onClearAll: {
                                    executeBroadcast(command: "clear", autoExecute: true)
                                },
                                onClose: {
                                    withAnimation(.spring()) {
                                        isMultiExecEnabled = false
                                    }
                                }
                            )
                            .padding(.top, 10)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Spotlight Quick Command Palette Overlay
                if showQuickPalette {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showQuickPalette = false
                            }
                        }
                    
                    QuickCommandPaletteView(
                        sessionStore: sessionStore,
                        openTabs: tabs,
                        onSelectTab: { tid in
                            switchToTab(tid)
                            showQuickPalette = false
                        },
                        onOpenSession: { sess in
                            openSessionInTab(sess, forceNew: true)
                            showQuickPalette = false
                        },
                        onExecuteCommand: { cmd in
                            executeCommandInActiveTerminal(cmd)
                            showQuickPalette = false
                        },
                        onClose: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showQuickPalette = false
                            }
                        }
                    )
                    .padding(.top, 50)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    // Quick Spotlight Palette Button
                    Button(action: {
                        HapticFeedbackHelper.shared.performGeneric()
                        withAnimation(.spring()) {
                            showQuickPalette.toggle()
                        }
                    }) {
                        Label("全局指令", systemImage: "command")
                    }
                    .help("极速指令与会话搜索面板 (⌘P / ⌘K)")
                    
                    // Multi-Exec Broadcast Toggle
                    Button(action: {
                        HapticFeedbackHelper.shared.performGeneric()
                        withAnimation(.spring()) {
                            isMultiExecEnabled.toggle()
                        }
                    }) {
                        Label("同步广播", systemImage: isMultiExecEnabled ? "bolt.horizontal.fill" : "bolt.horizontal")
                            .foregroundColor(isMultiExecEnabled ? .yellow : .primary)
                    }
                    .help("多终端同步输入广播模式 (⇧⌘B)")
                    
                    // Inspector Sidebar Toggle (Apple Standard)
                    Button(action: {
                        HapticFeedbackHelper.shared.performGeneric()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRightPanel.toggle()
                        }
                    }) {
                        Label("辅助面板", systemImage: "sidebar.trailing")
                            .foregroundColor(showRightPanel ? .accentColor : .primary)
                    }
                    .help("展开/收起右侧智能助手与命令库 (⌥⌘A)")
                }
            }
            // Native macOS 14+ Inspector Integration
            .inspector(isPresented: $showRightPanel) {
                VStack(spacing: 0) {
                    // Apple Pro Inspector Header (Unified Glass Capsule Switcher)
                    HStack(spacing: 8) {
                        // Sliding Capsule Switcher
                        HStack(spacing: 2) {
                            ForEach(RightPanelTab.allCases) { tab in
                                let isSelected = (activeRightTab == tab)
                                Button(action: {
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                        activeRightTab = tab
                                    }
                                    HapticFeedbackHelper.shared.performGeneric()
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: tab.iconName)
                                            .font(.system(size: 11))
                                        Text(tab.rawValue)
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    }
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                            .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 2, y: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        // Header Actions based on active tab
                        if activeRightTab == .ai {
                            Button(action: {
                                withAnimation { aiService.clearMessagesAndStartNewSession() }
                                HapticFeedbackHelper.shared.performGeneric()
                            }) {
                                Image(systemName: "plus.bubble")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("清空并开启新对话")
                            
                            Button(action: { showSettingsSheet = true }) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("配置大模型 API 与服务商")
                        }
                        
                        // Close inspector
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRightPanel = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(5)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("收起右侧检查器")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    Divider()
                    
                    if activeRightTab == .ai {
                        AIAssistantView(
                            aiService: aiService,
                            activeTerminalGetter: { activeTerminal },
                            allTerminalsGetter: {
                                var nodes: [(title: String, host: String, buffer: String)] = []
                                for tab in tabs {
                                    if let term = terminalViews[tab.id] {
                                        let buf = term.extractRecentBuffer(maxLines: 200)
                                        nodes.append((title: tab.title, host: tab.session.host, buffer: buf))
                                    }
                                }
                                return nodes
                            },
                            onExecuteCommand: { cmd in
                                executeCommandInActiveTerminal(cmd)
                            },
                            onInsertCommand: { cmd in
                                insertCommandInActiveTerminal(cmd)
                            }
                        )
                    } else {
                        SnippetManagerView(
                            onExecuteCommand: { cmd in
                                executeCommandInActiveTerminal(cmd)
                            },
                            onInsertCommand: { cmd in
                                insertCommandInActiveTerminal(cmd)
                            }
                        )
                    }
                }
                .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
        }
        .background(
            Group {
                ForEach(1...9, id: \.self) { num in
                    Button("") {
                        switchToTabIndex(num - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(num)")), modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }
                
                Button("") {
                    withAnimation(.spring()) {
                        showQuickPalette.toggle()
                    }
                }
                .keyboardShortcut("p", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                
                Button("") {
                    if let act = activeTab { closeTab(act) }
                }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                
                Button("") {
                    if let first = sessionStore.rootItems.first?.children?.first ?? sessionStore.rootItems.first {
                        openSessionInTab(first, forceNew: true)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            }
        )
        .onReceive(timer) { input in
            self.now = input
        }
        .onChange(of: activeTabId) { _, newId in
            if let id = newId, let term = terminalViews[id] {
                focusTerminal(term)
            }
        }
        .onAppear {
            setupKeyboardMonitor()
            setupMenuDispatcher()
        }
        .sheet(isPresented: $showSettingsSheet) {
            AIModelSettingsSheet(aiService: aiService)
        }
        .sheet(isPresented: $showNewSessionSheet) {
            SessionEditSheet(sessionStore: sessionStore, editingItem: nil)
        }
        .sheet(isPresented: $showNewGroupSheet) {
            SessionEditSheet(sessionStore: sessionStore, editingItem: SessionItem(name: "新建分组", isGroup: true, iconName: "folder.fill"))
        }
        .environmentObject(sessionStore)
    }
    
    private func setupMenuDispatcher() {
        let dispatcher = MenuEventDispatcher.shared
        dispatcher.onNewTab = { openDefaultSession(forceNew: true) }
        dispatcher.onCloseTab = { if let act = activeTab { closeTab(act) } }
        dispatcher.onCloseAllTabs = {
            tabs.removeAll()
            terminalViews.removeAll()
            activeTabId = nil
        }
        dispatcher.onNewSession = { showNewSessionSheet = true }
        dispatcher.onNewGroup = { showNewGroupSheet = true }
        dispatcher.onImport = { sessionStore.importFromFileWithOpenPanel() }
        dispatcher.onExport = { sessionStore.exportToFileWithSavePanel() }
        dispatcher.onClearTerminal = { executeCommandInActiveTerminal("clear") }
        dispatcher.onToggleBroadcast = { withAnimation { isMultiExecEnabled.toggle() } }
        dispatcher.onToggleAI = {
            activeRightTab = .ai
            withAnimation { showRightPanel.toggle() }
        }
        dispatcher.onToggleSnippets = {
            activeRightTab = .snippets
            withAnimation { showRightPanel.toggle() }
        }
        dispatcher.onNextTab = { switchToNextTab() }
        dispatcher.onPrevTab = { switchToPrevTab() }
        dispatcher.onDiagnoseCurrent = {
            withAnimation(.easeInOut(duration: 0.2)) {
                showRightPanel = true
                activeRightTab = .ai
            }
            let buffer = activeTerminal?.extractRecentBuffer(maxLines: 500) ?? ""
            aiService.send(
                userText: "请深度分析我当前终端的历史回滚日志与上下文，排查所有错误、异常与潜在隐患，并给出可行的修复命令和操作方案：",
                terminalContext: buffer
            )
        }
        dispatcher.onDiagnoseCluster = {
            withAnimation(.easeInOut(duration: 0.2)) {
                showRightPanel = true
                activeRightTab = .ai
            }
            var combinedContext = "【同网段多设备联合拓扑日志】:\n"
            for (idx, tab) in tabs.enumerated() {
                if let term = terminalViews[tab.id] {
                    let buf = term.extractRecentBuffer(maxLines: 200)
                    combinedContext += "\n=== [节点 \(idx + 1)] \(tab.title) (Host: \(tab.session.host)) ===\n\(buf)\n"
                }
            }
            aiService.send(
                userText: "我当前正在远程管理同一个局域网/业务集群下的多台协同设备。请结合各节点的日志输出进行联合排查，定位根因并给出修复方案：",
                terminalContext: combinedContext
            )
        }
        dispatcher.onCancelAI = { aiService.cancelCurrentGeneration() }
        dispatcher.onClearAI = { aiService.messages.removeAll() }
        dispatcher.onOpenSettings = { showSettingsSheet = true }
    }
    
    private func launchLocalTerminal() {
        let localSession = SessionItem(
            name: "本地终端 (Zsh)",
            iconName: "apple.terminal.fill",
            protocolType: .local,
            host: "localhost",
            username: NSUserName(),
            initialDirectory: "~"
        )
        openSessionInTab(localSession, forceNew: true)
    }
    
    private func openDefaultSession(forceNew: Bool = false) {
        if let firstChild = sessionStore.rootItems.first?.children?.first {
            openSessionInTab(firstChild, forceNew: forceNew)
        } else if let firstRoot = sessionStore.rootItems.first {
            openSessionInTab(firstRoot, forceNew: forceNew)
        } else {
            launchLocalTerminal()
        }
    }
    
    private func updateTabDirectory(tabId: UUID, directory: String) {
        if let idx = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs[idx].currentDirectory = directory
        }
    }
    
    private func switchToTab(_ tabId: UUID) {
        activeTabId = tabId
        if let term = terminalViews[tabId] {
            focusTerminal(term)
        }
    }
    
    private func switchToTabIndex(_ index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let targetId = tabs[index].id
        switchToTab(targetId)
    }
    
    private func switchToNextTab() {
        guard !tabs.isEmpty, let currId = activeTabId, let idx = tabs.firstIndex(where: { $0.id == currId }) else { return }
        let nextIdx = (idx + 1) % tabs.count
        switchToTabIndex(nextIdx)
    }
    
    private func switchToPrevTab() {
        guard !tabs.isEmpty, let currId = activeTabId, let idx = tabs.firstIndex(where: { $0.id == currId }) else { return }
        let prevIdx = (idx - 1 + tabs.count) % tabs.count
        switchToTabIndex(prevIdx)
    }
    
    private func focusTerminal(_ term: CustomTerminalView) {
        DispatchQueue.main.async {
            term.window?.makeFirstResponder(term)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            term.window?.makeFirstResponder(term)
        }
    }
    
    private func openSessionInTab(_ session: SessionItem, forceNew: Bool = false) {
        guard !session.isGroup else { return }
        
        if !forceNew, let existing = tabs.first(where: { $0.session.id == session.id }) {
            switchToTab(existing.id)
            return
        }
        
        let newTab = WorkspaceTab(session: session)
        tabs.append(newTab)
        activeTabId = newTab.id
    }
    
    private func closeTab(_ tab: WorkspaceTab) {
        terminalViews.removeValue(forKey: tab.id)
        
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: idx)
        
        if activeTabId == tab.id {
            if !tabs.isEmpty {
                let nextIdx = min(idx, tabs.count - 1)
                switchToTab(tabs[nextIdx].id)
            } else {
                activeTabId = nil
            }
        }
    }
    
    private func executeCommandInActiveTerminal(_ cmd: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        
        if isMultiExecEnabled {
            for (tabId, term) in terminalViews {
                term.sendCommand(command: cmd, autoExecute: true)
                historyStore.record(sessionId: tabId, command: cmd)
            }
            auditStore.logExecution(
                command: cmd,
                riskLevel: "Multi-Exec Broadcast",
                sessionName: "ALL_TERMINALS (\(terminalViews.count) nodes)",
                targetHost: "BROADCAST"
            )
            HapticFeedbackHelper.shared.performAlignment()
        } else if let term = activeTerminal {
            if let ownerTab = tabs.first(where: { terminalViews[$0.id] == term }), activeTabId != ownerTab.id {
                switchToTab(ownerTab.id)
            }
            
            term.sendCommand(command: cmd, autoExecute: true)
            if let sessId = activeTab?.session.id {
                historyStore.record(sessionId: sessId, command: cmd)
                auditStore.logExecution(
                    command: cmd,
                    riskLevel: "Normal",
                    sessionName: activeTab?.session.name ?? "Default",
                    targetHost: activeTab?.session.host ?? "127.0.0.1"
                )
            }
            HapticFeedbackHelper.shared.performGeneric()
        } else {
            if let defaultSession = sessionStore.rootItems.first?.children?.first ?? sessionStore.rootItems.first {
                openSessionInTab(defaultSession, forceNew: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let newTerm = self.activeTerminal {
                        newTerm.sendCommand(command: cmd, autoExecute: true)
                    }
                }
            }
        }
    }
    
    private func insertCommandInActiveTerminal(_ cmd: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        
        if isMultiExecEnabled {
            for (_, term) in terminalViews {
                term.sendCommand(command: cmd, autoExecute: false)
            }
        } else if let term = activeTerminal {
            if let ownerTab = tabs.first(where: { terminalViews[$0.id] == term }), activeTabId != ownerTab.id {
                switchToTab(ownerTab.id)
            }
            term.sendCommand(command: cmd, autoExecute: false)
        } else {
            if let defaultSession = sessionStore.rootItems.first?.children?.first ?? sessionStore.rootItems.first {
                openSessionInTab(defaultSession, forceNew: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let newTerm = self.activeTerminal {
                        newTerm.sendCommand(command: cmd, autoExecute: false)
                    }
                }
            }
        }
        HapticFeedbackHelper.shared.performGeneric()
    }
    
    private func executeBroadcast(command: String, autoExecute: Bool) {
        let clean = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        var targetCount = 0
        for (tabId, term) in terminalViews {
            if broadcastTargetTabIds.isEmpty || broadcastTargetTabIds.contains(tabId) {
                term.sendCommand(command: clean, autoExecute: autoExecute)
                if autoExecute {
                    historyStore.record(sessionId: tabId, command: clean)
                }
                targetCount += 1
            }
        }
        
        if autoExecute {
            auditStore.logExecution(
                command: clean,
                riskLevel: "Multi-Exec Broadcast",
                sessionName: "BROADCAST (\(targetCount) nodes)",
                targetHost: "CLUSTER_BROADCAST"
            )
            broadcastCommandText = ""
        }
        
        HapticFeedbackHelper.shared.performAlignment()
        
        withAnimation {
            broadcastFeedback = "⚡ 已向 \(targetCount) 个终端节点广播指令"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                self.broadcastFeedback = nil
            }
        }
    }
    
    private func sendBroadcastCtrlC() {
        let ctrlCData = Data([0x03])
        var count = 0
        for (tabId, term) in terminalViews {
            if broadcastTargetTabIds.isEmpty || broadcastTargetTabIds.contains(tabId) {
                term.sendBroadcastData(ctrlCData)
                count += 1
            }
        }
        HapticFeedbackHelper.shared.performLevelChange()
        withAnimation {
            broadcastFeedback = "⚡ 已向 \(count) 个终端发送 Ctrl+C 中断信号"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                self.broadcastFeedback = nil
            }
        }
    }
    
    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.isMultiExecEnabled, self.enableLiveKeyboardMirroring else { return event }
            
            if let window = NSApp.keyWindow, let firstResponder = window.firstResponder as? NSView {
                let isTerminalFocus = firstResponder is CustomTerminalView || String(describing: type(of: firstResponder)).contains("Terminal")
                if isTerminalFocus, let chars = event.characters, !chars.isEmpty {
                    for (tabId, term) in self.terminalViews where tabId != self.activeTabId {
                        if self.broadcastTargetTabIds.isEmpty || self.broadcastTargetTabIds.contains(tabId) {
                            term.sendBroadcastCharacters(chars)
                        }
                    }
                }
            }
            return event
        }
    }
}

// MARK: - Floating Glass HUD Broadcast Center (macOS Style)
struct FloatingBroadcastHUDView: View {
    let tabs: [WorkspaceTab]
    @Binding var targetIds: Set<UUID>
    @Binding var enableMirroring: Bool
    @Binding var commandText: String
    let feedbackText: String?
    
    let onExecute: (String) -> Void
    let onInsert: (String) -> Void
    let onSendCtrlC: () -> Void
    let onClearAll: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header & Target Selection Bar
            HStack(spacing: 8) {
                Label("同步广播中心", systemImage: "bolt.horizontal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.yellow)
                
                Text("目标会话:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { tab in
                            let isSelected = targetIds.isEmpty || targetIds.contains(tab.id)
                            Button(action: {
                                if targetIds.isEmpty {
                                    var all = Set(tabs.map { $0.id })
                                    all.remove(tab.id)
                                    targetIds = all
                                } else if targetIds.contains(tab.id) {
                                    targetIds.remove(tab.id)
                                } else {
                                    targetIds.insert(tab.id)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(isSelected ? .green : .secondary)
                                    Text(tab.title)
                                        .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isSelected ? Color.yellow.opacity(0.2) : Color.secondary.opacity(0.12))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Spacer()
                
                Toggle("实时键盘镜像", isOn: $enableMirroring)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help("开启后，任意终端击键将实时镜像给所有勾选终端")
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭广播模式")
            }
            
            // Broadcast Command Input Box
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                    
                    TextField("输入命令按回车，将同时在以上已勾选的会话中并发执行...", text: $commandText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            onExecute(commandText)
                        }
                    
                    if !commandText.isEmpty {
                        Button(action: { commandText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.textBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 1.5)
                )
                
                Button(action: { onExecute(commandText) }) {
                    Label("广播执行 (Enter)", systemImage: "paperplane.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundColor(.black)
                .controlSize(.regular)
                .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                if let feedback = feedbackText {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 11))
                        Text(feedback)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                    .transition(.opacity)
                }
                
                Button(action: { onInsert(commandText) }) {
                    Text("填入")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                Menu {
                    Button("广播发送 Ctrl+C 中断", action: onSendCtrlC)
                    Button("广播执行 clear 清屏", action: onClearAll)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Materialized Native TabBar View with Drag & Drop
struct TabBarView: View {
    @Binding var tabs: [WorkspaceTab]
    let activeTabId: UUID?
    let onSelectTab: (WorkspaceTab) -> Void
    let onCloseTab: (WorkspaceTab) -> Void
    let onNewTab: () -> Void
    let onOpenPalette: () -> Void
    
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var draggedTab: WorkspaceTab?
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        let isActive = (tab.id == activeTabId)
                        HStack(spacing: 6) {
                            // Activity pulse dot
                            Circle()
                                .fill(isActive ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            
                            // Protocol icon
                            Image(systemName: tab.session.iconName)
                                .font(.system(size: 11))
                                .foregroundColor(protocolColor(tab.session.protocolType))
                            
                            // Title
                            Text(tab.title)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .lineLimit(1)
                            
                            // Real Uptime / Duration Badge
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .font(.system(size: 8))
                                Text(tab.uptimeFormatted)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                            
                            // Shortcut badge (Cmd+1, Cmd+2 ...)
                            if index < 9 {
                                Text("⌘\(index + 1)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            
                            // Close button
                            Button(action: { onCloseTab(tab) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(3)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectTab(tab)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            
            // New Tab Button
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help("新建标签页 (⌘T)")
            
            // Quick Search / Palette Button
            Button(action: onOpenPalette) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help("快速指令与搜索 (⌘P)")
            
            Spacer()
        }
        .background(.regularMaterial)
    }
    
    private func protocolColor(_ proto: SessionProtocol) -> Color {
        switch proto {
        case .ssh: return .green
        case .sftp: return .teal
        case .scp: return .cyan
        case .telnet: return .orange
        case .serial: return .blue
        case .ble: return .indigo
        case .local: return .accentColor
        case .vnc: return .purple
        case .ftp: return .teal
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let onLaunchLocalTerminal: () -> Void
    let onNewSession: () -> Void
    
    @State private var isHoverLocal: Bool = false
    @State private var isHoverNew: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: .accentColor.opacity(0.25), radius: 10, x: 0, y: 4)
                
                Text(">_")
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            .padding(.bottom, 4)
            
            VStack(spacing: 8) {
                Text("智能运维终端就绪")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("启动本地终端、新增远程连接，或从左侧会话树快速双击连接。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 14) {
                Button(action: onLaunchLocalTerminal) {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.terminal.fill")
                            .font(.system(size: 14))
                        Text("启动本地终端 (⇧⌘T)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHoverLocal ? Color.secondary.opacity(0.25) : Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoverLocal = $0 }
                
                Button(action: onNewSession) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                        Text("新增会话 (⌘N)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHoverNew ? Color.secondary.opacity(0.25) : Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoverNew = $0 }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Global Menu Event Dispatcher
final class MenuEventDispatcher {
    static let shared = MenuEventDispatcher()
    
    var onNewTab: (() -> Void)?
    var onCloseTab: (() -> Void)?
    var onCloseAllTabs: (() -> Void)?
    var onNewSession: (() -> Void)?
    var onNewGroup: (() -> Void)?
    var onImport: (() -> Void)?
    var onExport: (() -> Void)?
    var onClearTerminal: (() -> Void)?
    var onToggleBroadcast: (() -> Void)?
    var onToggleAI: (() -> Void)?
    var onToggleSnippets: (() -> Void)?
    var onNextTab: (() -> Void)?
    var onPrevTab: (() -> Void)?
    var onDiagnoseCurrent: (() -> Void)?
    var onDiagnoseCluster: (() -> Void)?
    var onCancelAI: (() -> Void)?
    var onClearAI: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    
    private init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .AIConsoleNewTab, object: nil, queue: .main) { [weak self] _ in self?.onNewTab?() }
        nc.addObserver(forName: .AIConsoleCloseTab, object: nil, queue: .main) { [weak self] _ in self?.onCloseTab?() }
        nc.addObserver(forName: .AIConsoleCloseAllTabs, object: nil, queue: .main) { [weak self] _ in self?.onCloseAllTabs?() }
        nc.addObserver(forName: .AIConsoleNewSessionDialog, object: nil, queue: .main) { [weak self] _ in self?.onNewSession?() }
        nc.addObserver(forName: .AIConsoleNewGroupDialog, object: nil, queue: .main) { [weak self] _ in self?.onNewGroup?() }
        nc.addObserver(forName: .AIConsoleImportConfig, object: nil, queue: .main) { [weak self] _ in self?.onImport?() }
        nc.addObserver(forName: .AIConsoleExportConfig, object: nil, queue: .main) { [weak self] _ in self?.onExport?() }
        nc.addObserver(forName: .AIConsoleClearTerminal, object: nil, queue: .main) { [weak self] _ in self?.onClearTerminal?() }
        nc.addObserver(forName: .AIConsoleToggleBroadcast, object: nil, queue: .main) { [weak self] _ in self?.onToggleBroadcast?() }
        nc.addObserver(forName: .AIConsoleToggleAIPanel, object: nil, queue: .main) { [weak self] _ in self?.onToggleAI?() }
        nc.addObserver(forName: .AIConsoleToggleSnippetsPanel, object: nil, queue: .main) { [weak self] _ in self?.onToggleSnippets?() }
        nc.addObserver(forName: .AIConsoleNextTab, object: nil, queue: .main) { [weak self] _ in self?.onNextTab?() }
        nc.addObserver(forName: .AIConsolePrevTab, object: nil, queue: .main) { [weak self] _ in self?.onPrevTab?() }
        nc.addObserver(forName: .AIConsoleDiagnoseCurrent, object: nil, queue: .main) { [weak self] _ in self?.onDiagnoseCurrent?() }
        nc.addObserver(forName: .AIConsoleDiagnoseCluster, object: nil, queue: .main) { [weak self] _ in self?.onDiagnoseCluster?() }
        nc.addObserver(forName: .AIConsoleCancelAIGeneration, object: nil, queue: .main) { [weak self] _ in self?.onCancelAI?() }
        nc.addObserver(forName: .AIConsoleClearAIChat, object: nil, queue: .main) { [weak self] _ in self?.onClearAI?() }
        nc.addObserver(forName: .AIConsoleOpenSettings, object: nil, queue: .main) { [weak self] _ in self?.onOpenSettings?() }
    }
}
