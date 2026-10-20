import SwiftUI

public enum RightPanelTab: String, CaseIterable, Identifiable {
    case ai = "AI 助手"
    case snippets = "常用命令"
    case recording = "会话录制"
    
    public var id: String { rawValue }
    public var iconName: String {
        switch self {
        case .ai: return "sparkles"
        case .snippets: return "terminal"
        case .recording: return "record.circle"
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
    @State private var showSettingsSheet: Bool = false
    @State private var showNewSessionSheet: Bool = false
    @State private var showNewGroupSheet: Bool = false
    @State private var showQuickPalette: Bool = false
    @State private var isBroadcastEnabled: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var hoveredTabId: UUID?
    @ObservedObject private var recordingManager = RecordingManager.shared
    
    // Auto-update uptime timer for active sessions
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    public init() {}
    
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
                // Main Terminal Canvas Area
                terminalCanvasView
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                    .padding(.top, 2)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                
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
            .toolbar {
                // Integrated Native Session Tabs in Window Titlebar (shown when tabs exist)
                if !tabs.isEmpty {
                    ToolbarItem(placement: .principal) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                                    let isActive = (tab.id == activeTabId)
                                    let isHovered = (hoveredTabId == tab.id)
                                    let isRec = recordingManager.isRecording(tabId: tab.id)
                                    
                                    HStack(spacing: 6) {
                                        // Protocol icon
                                        Image(systemName: tab.session.iconName)
                                            .font(.system(size: 11))
                                            .foregroundColor(protocolColor(tab.session.protocolType))
                                        
                                        // Title
                                        Text(tab.title)
                                            .font(.system(size: 12, weight: isActive ? .medium : .regular))
                                            .foregroundColor(isActive ? .primary : .secondary)
                                            .lineLimit(1)
                                        
                                        // Pulsing Recording Indicator
                                        if isRec {
                                            HStack(spacing: 2) {
                                                Circle()
                                                    .fill(Color.red)
                                                    .frame(width: 5, height: 5)
                                                Text("REC")
                                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                                    .foregroundColor(.red)
                                            }
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(Color.red.opacity(0.12))
                                            .cornerRadius(3)
                                        }
                                        
                                        // Close button
                                        Button(action: { closeTab(tab) }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.secondary)
                                                .frame(width: 14, height: 14)
                                                .background(Color.secondary.opacity(isHovered || isActive ? 0.12 : 0))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .opacity(isHovered || isActive || tabs.count > 1 ? 1 : 0)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isActive ? Color(NSColor.controlBackgroundColor) : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
                                            .shadow(color: isActive ? Color.black.opacity(0.06) : Color.clear, radius: 1, y: 1)
                                    )
                                    .contentShape(Rectangle())
                                    .onHover { h in
                                        hoveredTabId = h ? tab.id : nil
                                    }
                                    .onTapGesture {
                                        HapticFeedbackHelper.shared.performGeneric()
                                        switchToTab(tab.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                        }
                        .frame(maxWidth: 720)
                    }
                }
                
                // Primary Action: Right Inspector Toggle Button (Apple Standard)
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRightPanel.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.trailing")
                            .font(.system(size: 12))
                            .foregroundColor(showRightPanel ? .accentColor : .secondary)
                            .frame(width: 26, height: 26)
                            .background(Color.secondary.opacity(showRightPanel ? 0.12 : 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("展开/收起右侧辅助面板 (⌥⌘A)")
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
                                    HStack(spacing: 4) {
                                        Image(systemName: tab.iconName)
                                            .font(.system(size: 11))
                                        Text(tab.rawValue)
                                            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                                    }
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                            .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(7)
                        
                        Spacer()
                        
                        // Header Actions based on active tab
                        if activeRightTab == .ai {
                            Button(action: {
                                withAnimation { aiService.clearMessagesAndStartNewSession() }
                                HapticFeedbackHelper.shared.performGeneric()
                            }) {
                                Image(systemName: "plus.bubble")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 22, height: 22)
                                    .background(Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .help("清空并开启新对话")
                            
                            Button(action: { showSettingsSheet = true }) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 22, height: 22)
                                    .background(Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
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
                                .frame(width: 22, height: 22)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("收起右侧检查器")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    
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
                    } else if activeRightTab == .snippets {
                        SnippetManagerView(
                            onExecuteCommand: { cmd in
                                executeCommandInActiveTerminal(cmd)
                            },
                            onInsertCommand: { cmd in
                                insertCommandInActiveTerminal(cmd)
                            }
                        )
                    } else if activeRightTab == .recording {
                        SessionRecordingView(
                            activeTerminalGetter: { activeTerminal },
                            currentSession: activeTab?.session,
                            activeTabId: activeTabId
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
                .padding(.top, 2)
                .padding(.trailing, 6)
                .padding(.bottom, 6)
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
    
    @ViewBuilder
    private var terminalCanvasView: some View {
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
                    terminalTabContent(for: tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(isCurrent ? 1 : 0)
                        .allowsHitTesting(isCurrent)
                        .zIndex(isCurrent ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func terminalTabContent(for tab: WorkspaceTab) -> some View {
        switch tab.session.protocolType {
        case .ssh, .telnet, .serial, .ble, .local:
            TerminalSplitView(
                tabId: tab.id,
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
                onActiveTerminalChanged: { activeSubTerm in
                    self.terminalViews[tab.id] = activeSubTerm
                },
                onDiagnoseRequested: { contextSnippet in
                    HapticFeedbackHelper.shared.performAlignment()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRightPanel = true
                        activeRightTab = .ai
                    }
                    aiService.selectSession(tabId: tab.id, title: tab.title)
                    aiService.send(
                        userText: "检测到终端产生报错，请针对以下报错信息进行快速根因分析，并给出修复命令：",
                        terminalContext: contextSnippet,
                        targetSessionId: tab.id
                    )
                }
            )
        case .vnc:
            VNCView(session: tab.session)
        case .sftp, .scp, .ftp:
            FTPBrowserView(session: tab.session)
        }
    }
    
    private func setupMenuDispatcher() {
        let dispatcher = MenuEventDispatcher.shared
        dispatcher.onToggleSidebar = {
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = (columnVisibility == .all ? .detailOnly : .all)
            }
        }
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
        if let tab = tabs.first(where: { $0.id == tabId }) {
            aiService.selectSession(tabId: tabId, title: tab.title)
        }
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
        aiService.selectSession(tabId: newTab.id, title: newTab.title)
    }
    
    private func closeTab(_ tab: WorkspaceTab) {
        // Safe shutdown for active recording stream to prevent truncated logs
        if RecordingManager.shared.isRecording(tabId: tab.id) {
            _ = RecordingManager.shared.stopRecording(tabId: tab.id)
        }
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
        
        // Multi-Execution Broadcast Mode: Send simultaneously to all open tabs
        if isBroadcastEnabled && tabs.count > 1 {
            for tab in tabs {
                if let term = terminalViews[tab.id] {
                    term.sendCommand(command: cmd, autoExecute: true)
                }
            }
            HapticFeedbackHelper.shared.performAlignment()
            return
        }
        
        if let term = activeTerminal {
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
        
        if let term = activeTerminal {
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

// MARK: - Materialized Native TabBar View with Drag & Drop
struct TabBarView: View {
    @Binding var tabs: [WorkspaceTab]
    let activeTabId: UUID?
    @Binding var isBroadcastEnabled: Bool
    let onSelectTab: (WorkspaceTab) -> Void
    let onCloseTab: (WorkspaceTab) -> Void
    let onNewTab: () -> Void
    let onOpenPalette: () -> Void
    @Binding var showRightPanel: Bool
    let onToggleRightPanel: () -> Void
    
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var recordingManager = RecordingManager.shared
    @State private var hoveredTabId: UUID?
    
    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        let isActive = (tab.id == activeTabId)
                        let isHovered = (hoveredTabId == tab.id)
                        let isRec = recordingManager.isRecording(tabId: tab.id)
                        
                        HStack(spacing: 6) {
                            // Protocol icon
                            Image(systemName: tab.session.iconName)
                                .font(.system(size: 11))
                                .foregroundColor(protocolColor(tab.session.protocolType))
                            
                            // Title
                            Text(tab.title)
                                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                                .foregroundColor(isActive ? .primary : .secondary)
                                .lineLimit(1)
                            
                            // Pulsing Recording Indicator
                            if isRec {
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 5, height: 5)
                                    Text("REC")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(3)
                            }
                            
                            // Close button (show on hover or when multiple tabs)
                            Button(action: { onCloseTab(tab) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 14, height: 14)
                                    .background(Color.secondary.opacity(isHovered || isActive ? 0.12 : 0))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .opacity(isHovered || isActive || tabs.count > 1 ? 1 : 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isActive ? Color(NSColor.controlBackgroundColor) : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
                                .shadow(color: isActive ? Color.black.opacity(0.06) : Color.clear, radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                        .onHover { h in
                            hoveredTabId = h ? tab.id : nil
                        }
                        .onTapGesture {
                            onSelectTab(tab)
                        }
                    }
                    
                    // New Tab Button right next to tabs
                    Button(action: onNewTab) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("新建终端标签 (⌘T)")
                    .padding(.leading, 2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Broadcast Multi-Execution Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isBroadcastEnabled.toggle()
                }
                HapticFeedbackHelper.shared.performAlignment()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isBroadcastEnabled ? "antenna.radiowaves.left.and.right" : "dot.radiowaves.up.forward")
                        .font(.system(size: 11))
                    if isBroadcastEnabled {
                        Text("广播同步中")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundColor(isBroadcastEnabled ? .orange : .secondary)
                .padding(.horizontal, isBroadcastEnabled ? 8 : 6)
                .padding(.vertical, 4)
                .background(isBroadcastEnabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(isBroadcastEnabled ? "广播模式已开启：执行命令将同步打入所有已打开的终端" : "开启广播同步模式：将命令同时打入所有终端")
            
            // Inspector Toggle Button (Apple Standard)
            Button(action: onToggleRightPanel) {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 12))
                    .foregroundColor(showRightPanel ? .accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(showRightPanel ? 0.12 : 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("展开/收起右侧辅助面板 (⌥⌘A)")
            .padding(.trailing, 8)
        }
        .background(.ultraThinMaterial)
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
    
    var onToggleSidebar: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onCloseTab: (() -> Void)?
    var onCloseAllTabs: (() -> Void)?
    var onNewSession: (() -> Void)?
    var onNewGroup: (() -> Void)?
    var onImport: (() -> Void)?
    var onExport: (() -> Void)?
    var onClearTerminal: (() -> Void)?
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
        nc.addObserver(forName: .AIConsoleToggleSidebar, object: nil, queue: .main) { [weak self] _ in self?.onToggleSidebar?() }
        nc.addObserver(forName: .AIConsoleNewTab, object: nil, queue: .main) { [weak self] _ in self?.onNewTab?() }
        nc.addObserver(forName: .AIConsoleCloseTab, object: nil, queue: .main) { [weak self] _ in self?.onCloseTab?() }
        nc.addObserver(forName: .AIConsoleCloseAllTabs, object: nil, queue: .main) { [weak self] _ in self?.onCloseAllTabs?() }
        nc.addObserver(forName: .AIConsoleNewSessionDialog, object: nil, queue: .main) { [weak self] _ in self?.onNewSession?() }
        nc.addObserver(forName: .AIConsoleNewGroupDialog, object: nil, queue: .main) { [weak self] _ in self?.onNewGroup?() }
        nc.addObserver(forName: .AIConsoleImportConfig, object: nil, queue: .main) { [weak self] _ in self?.onImport?() }
        nc.addObserver(forName: .AIConsoleExportConfig, object: nil, queue: .main) { [weak self] _ in self?.onExport?() }
        nc.addObserver(forName: .AIConsoleClearTerminal, object: nil, queue: .main) { [weak self] _ in self?.onClearTerminal?() }
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
