import SwiftUI
import UniformTypeIdentifiers

public struct TerminalSplitView: View {
    @ObservedObject private var sessionStore: SessionStore = .shared
    @ObservedObject private var themeStore: ThemeStore = .shared
    
    public let tabId: UUID
    let session: SessionItem
    let onDirectoryChanged: ((String) -> Void)?
    let onTerminalReady: ((CustomTerminalView) -> Void)?
    let onActiveTerminalChanged: ((CustomTerminalView) -> Void)?
    let onDiagnoseRequested: ((String) -> Void)?
    
    @State private var isSplit: Bool = false
    @State private var splitOrientation: Axis = .horizontal
    @State private var activePane: Int = 1
    
    // Search state
    @State private var showSearch: Bool = false
    @State private var searchText: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var searchIndex: Int = 0
    @State private var searchTotal: Int = 0
    
    @State private var isRecordingSession: Bool = false
    @State private var isDropTarget: Bool = false
    @State private var currentPath: String = "~"
    
    // Persistent Terminal instances to prevent losing history/state on split layout changes
    @State private var primaryTerminal: CustomTerminalView?
    @State private var secondaryTerminal: CustomTerminalView?
    @State private var secondarySession: SessionItem?
    
    @FocusState private var isSearchFocused: Bool
    
    // Active Error Notification Toast
    @State private var activeErrorEvent: DetectedErrorEvent?
    
    public init(
        tabId: UUID = UUID(),
        session: SessionItem,
        onDirectoryChanged: ((String) -> Void)? = nil,
        onTerminalReady: ((CustomTerminalView) -> Void)? = nil,
        onActiveTerminalChanged: ((CustomTerminalView) -> Void)? = nil,
        onDiagnoseRequested: ((String) -> Void)? = nil
    ) {
        self.tabId = tabId
        self.session = session
        self.onDirectoryChanged = onDirectoryChanged
        self.onTerminalReady = onTerminalReady
        self.onActiveTerminalChanged = onActiveTerminalChanged
        self.onDiagnoseRequested = onDiagnoseRequested
    }
    
    private var allAvailableSessions: [SessionItem] {
        var list: [SessionItem] = []
        func collect(items: [SessionItem]) {
            for item in items {
                if item.isGroup {
                    if let ch = item.children { collect(items: ch) }
                } else {
                    list.append(item)
                }
            }
        }
        collect(items: sessionStore.rootItems)
        return list
    }
    
    public var body: some View {
        VStack(spacing: 0) {

            
            // Interactive Search & Highlight Bar
            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    
                    TextField("在终端中查找 (Enter 下一个)...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                        .onSubmit {
                            findNext()
                        }
                        .onChange(of: searchText) { _, _ in
                            updateSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Text(searchTotal > 0 ? "\(searchIndex)/\(searchTotal)" : "无匹配")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(searchTotal > 0 ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(searchTotal > 0 ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Button(action: {
                        isCaseSensitive.toggle()
                        updateSearch()
                    }) {
                        Text("Aa")
                            .font(.system(size: 11, weight: isCaseSensitive ? .bold : .regular))
                            .foregroundColor(isCaseSensitive ? .accentColor : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(isCaseSensitive ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("区分大小写")
                    
                    Button(action: findPrevious) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(searchTotal == 0)
                    .help("查找上一个")
                    
                    Button(action: findNext) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(searchTotal == 0)
                    .help("查找下一个 (Enter)")
                    
                    Button(action: {
                        showSearch = false
                        searchText = ""
                        primaryTerminal?.clearSearch()
                        secondaryTerminal?.clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("关闭搜索 (ESC)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.secondary.opacity(0.2)),
                    alignment: .bottom
                )
            }
            
            // Dedicated Serial Engineering Quick Action Bar (Only for serial protocol)
            if session.protocolType == .serial {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text("串口硬件调测:")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.secondary)
                    
                    Button(action: {
                        let target = (activePane == 1 ? primaryTerminal : secondaryTerminal) ?? primaryTerminal
                        target?.sendWakeupKeys()
                        HapticFeedbackHelper.shared.performGeneric()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                            Text("唤醒终端 (Enter x2)")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("向串口发送两次回车，唤醒交换机或嵌入式 Linux 控制台提示符")
                    
                    Button(action: {
                        let target = (activePane == 1 ? primaryTerminal : secondaryTerminal) ?? primaryTerminal
                        target?.sendStopAutoboot()
                        HapticFeedbackHelper.shared.performGeneric()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "hand.raised.fill")
                            Text("打断引导 (Autoboot)")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("在设备开机阶段高频发送空格与回车，抢占打断 U-Boot/BIOS 倒计时进入引导终端")
                    
                    Button(action: {
                        let target = (activePane == 1 ? primaryTerminal : secondaryTerminal) ?? primaryTerminal
                        target?.sendBreakSignal()
                        HapticFeedbackHelper.shared.performGeneric()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.circle")
                            Text("发送中断 (Ctrl+C / Break)")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("发送硬件中断信号 / 终止当前死循环进程")
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.06))
            }
            
            // Terminal Panes (with Drag & Drop upload support & Min Size Protection)
            ZStack {
                if isSplit {
                    if splitOrientation == .horizontal {
                        HSplitView {
                            paneContainer(paneIndex: 1, targetSession: session, isPrimary: true)
                                .frame(minWidth: 220)
                            
                            paneContainer(paneIndex: 2, targetSession: secondarySession ?? session, isPrimary: false)
                                .frame(minWidth: 220)
                        }
                    } else {
                        VSplitView {
                            paneContainer(paneIndex: 1, targetSession: session, isPrimary: true)
                                .frame(minHeight: 140)
                            
                            paneContainer(paneIndex: 2, targetSession: secondarySession ?? session, isPrimary: false)
                                .frame(minHeight: 140)
                        }
                    }
                } else {
                    paneContainer(paneIndex: 1, targetSession: session, isPrimary: true)
                }
                
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.1))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.accentColor)
                                Text("释放文件以填入路径或上传到当前目录")
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            }
                        )
                }
                
                // Realtime AI Error Diagnosis Floating Toast
                if let event = activeErrorEvent {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3)
                                    .foregroundColor(.yellow)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("检测到终端异常报错")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(event.summary)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Button(action: {
                                    onDiagnoseRequested?(event.contextSnippet)
                                    withAnimation { activeErrorEvent = nil }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                        Text("AI 诊断")
                                    }
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                
                                Button(action: {
                                    withAnimation { activeErrorEvent = nil }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.yellow.opacity(0.6), lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            .onAppear {
                TerminalErrorDetector.shared.registerListener(for: tabId) { event in
                    withAnimation(.spring()) {
                        self.activeErrorEvent = event
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                        if self.activeErrorEvent?.id == event.id {
                            withAnimation {
                                self.activeErrorEvent = nil
                            }
                        }
                    }
                }
            }
            .onDisappear {
                TerminalErrorDetector.shared.unregisterListener(for: tabId)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let fileUrl = url {
                        DispatchQueue.main.async {
                            let target = (activePane == 1) ? primaryTerminal : (secondaryTerminal ?? primaryTerminal)
                            target?.handleDroppedFile(url: fileUrl)
                        }
                    }
                }
                return true
            }
        }
    }
    
    private func toggleSplitMode(to orientation: Axis) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if isSplit && splitOrientation == orientation {
                isSplit = false
                focusPane(1)
            } else {
                isSplit = true
                splitOrientation = orientation
                if secondarySession == nil {
                    secondarySession = session
                }
            }
        }
    }
    
    private func focusPane(_ paneIndex: Int) {
        self.activePane = paneIndex
        let target = (paneIndex == 1) ? primaryTerminal : secondaryTerminal
        if let term = target {
            onActiveTerminalChanged?(term)
            DispatchQueue.main.async {
                term.window?.makeFirstResponder(term)
            }
        }
    }
    
    @ViewBuilder
    private func paneContainer(paneIndex: Int, targetSession: SessionItem, isPrimary: Bool) -> some View {
        let isFocused = (activePane == paneIndex)
        
        VStack(spacing: 0) {
            if isSplit {
                // High-Distinction Pane Header Bar
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isFocused ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .shadow(color: isFocused ? Color.green.opacity(0.8) : Color.clear, radius: 3)
                        
                        Text(isPrimary ? "主屏 #1" : "副屏 #2")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isFocused ? .accentColor : .secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Label(targetSession.name, systemImage: targetSession.iconName)
                            .font(.system(size: 11, weight: isFocused ? .semibold : .regular))
                            .foregroundColor(isFocused ? .primary : .secondary)
                        
                        Text(sessionSubtitle(targetSession))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    if !isPrimary {
                        Menu {
                            Text("— 切换副屏连接会话 —")
                            ForEach(allAvailableSessions) { item in
                                Button(action: {
                                    switchSecondarySession(to: item)
                                }) {
                                    HStack {
                                        Text(item.name)
                                        if item.id == targetSession.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                Text("更换会话")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton)
                        .help("在副屏中连接其他设备或会话")
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isSplit = false
                                focusPane(1)
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(4)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("关闭副终端屏")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isFocused ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.7))
                .onTapGesture {
                    focusPane(paneIndex)
                }
                
                Divider()
            }
            
            // Persistent Terminal Instance Representation with breathing room padding
            TerminalContainerView(
                session: targetSession,
                tabId: tabId,
                theme: themeStore.currentTheme,
                fontSize: themeStore.fontSize,
                existingTerminal: isPrimary ? primaryTerminal : secondaryTerminal,
                onDirectoryChanged: isPrimary ? { dir in
                    self.currentPath = dir
                    self.onDirectoryChanged?(dir)
                } : nil,
                onTerminalReady: { term in
                    if isPrimary {
                        self.primaryTerminal = term
                        self.onTerminalReady?(term)
                        self.onActiveTerminalChanged?(term)
                    } else {
                        self.secondaryTerminal = term
                        if self.activePane == 2 {
                            self.onActiveTerminalChanged?(term)
                        }
                    }
                },
                onFocused: {
                    self.activePane = paneIndex
                    let target = isPrimary ? (self.primaryTerminal) : (self.secondaryTerminal ?? self.primaryTerminal)
                    if let t = target {
                        self.onActiveTerminalChanged?(t)
                    }
                }
            )
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .background(Color(themeStore.currentTheme.backgroundColor))
            .opacity(isSplit && !isFocused ? 0.88 : 1.0)
        }
        .clipShape(RoundedRectangle(cornerRadius: isSplit ? 6 : 0))
        .overlay(
            Group {
                if isSplit {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isFocused ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isFocused ? 1.5 : 0.5)
                }
            }
        )
        .padding(isSplit ? 3 : 0)
        .onTapGesture {
            focusPane(paneIndex)
        }
    }
    
    private func switchSecondarySession(to newSession: SessionItem) {
        self.secondarySession = newSession
        self.secondaryTerminal = nil // Will spawn new session in pane 2
        self.activePane = 2
    }
    
    private func sessionSubtitle(_ item: SessionItem) -> String {
        if item.protocolType == .serial {
            return "\(item.serialDevicePath ?? "/dev/cu.usbserial")"
        } else if item.protocolType == .local {
            return "本地"
        } else {
            return "\(item.username)@\(item.host):\(item.port)"
        }
    }
    
    private func updateSearch() {
        let term = (activePane == 1) ? primaryTerminal : (secondaryTerminal ?? primaryTerminal)
        guard let t = term else { return }
        let res = t.performSearch(query: searchText, caseSensitive: isCaseSensitive)
        self.searchIndex = res.index
        self.searchTotal = res.total
    }
    
    private func findNext() {
        let term = (activePane == 1) ? primaryTerminal : (secondaryTerminal ?? primaryTerminal)
        guard let t = term else { return }
        let res = t.findNextMatch(query: searchText, caseSensitive: isCaseSensitive)
        self.searchIndex = res.index
        self.searchTotal = res.total
    }
    
    private func findPrevious() {
        let term = (activePane == 1) ? primaryTerminal : (secondaryTerminal ?? primaryTerminal)
        guard let t = term else { return }
        let res = t.findPreviousMatch(query: searchText, caseSensitive: isCaseSensitive)
        self.searchIndex = res.index
        self.searchTotal = res.total
    }
}
