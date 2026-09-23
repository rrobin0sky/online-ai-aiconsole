import SwiftUI
import UniformTypeIdentifiers

public struct TerminalSplitView: View {
    @ObservedObject private var sessionStore: SessionStore = .shared
    @ObservedObject private var themeStore: ThemeStore = .shared
    
    let session: SessionItem
    let onDirectoryChanged: ((String) -> Void)?
    let onTerminalReady: ((CustomTerminalView) -> Void)?
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
        session: SessionItem,
        onDirectoryChanged: ((String) -> Void)? = nil,
        onTerminalReady: ((CustomTerminalView) -> Void)? = nil,
        onDiagnoseRequested: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.onDirectoryChanged = onDirectoryChanged
        self.onTerminalReady = onTerminalReady
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
            // Terminal Top Toolbar
            HStack(spacing: 10) {
                // Session title & recording indicator
                HStack(spacing: 6) {
                    if isRecordingSession {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                    Label(session.name, systemImage: session.iconName)
                        .font(.system(size: 13, weight: .medium))
                    
                    // OSC 7 Current Working Directory Badge
                    Text(currentPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Crash-Proof Live Recording Button
                Button(action: {
                    let term = (activePane == 1) ? primaryTerminal : (secondaryTerminal ?? primaryTerminal)
                    guard let t = term else { return }
                    if t.isRecording {
                        _ = t.stopRecording()
                        self.isRecordingSession = false
                    } else {
                        let activeSession = (activePane == 1) ? session : (secondarySession ?? session)
                        t.startRecording(sessionName: activeSession.name) { started, _ in
                            self.isRecordingSession = started
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isRecordingSession ? "record.circle.fill" : "record.circle")
                            .foregroundColor(isRecordingSession ? .red : .primary)
                        Text(isRecordingSession ? "停止录制" : "开始录制")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(isRecordingSession ? "停止实时录制并在访达中定位日志文件" : "选择保存位置并开启防死机实时写入录制")
                
                // Search toggle
                Button(action: {
                    showSearch.toggle()
                    if showSearch {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSearchFocused = true
                        }
                    } else {
                        primaryTerminal?.clearSearch()
                        secondaryTerminal?.clearSearch()
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(showSearch ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("在终端中高亮搜索 (Cmd+F)")
                
                // AI Diagnosis Trigger
                Button(action: {
                    let term = (activePane == 1) ? primaryTerminal : (secondaryTerminal ?? primaryTerminal)
                    if let buf = term?.extractRecentBuffer(maxLines: 80), !buf.isEmpty {
                        onDiagnoseRequested?(buf)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("AI 诊断")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("提取当前活跃终端输出进行 AI 根因分析")
                
                // Theme & Appearance Menu
                Menu {
                    Text("— 终端配色主题 —")
                    ForEach(TerminalTheme.allThemes) { theme in
                        Button(action: {
                            themeStore.setTheme(theme)
                        }) {
                            HStack {
                                Text(theme.name)
                                if theme.id == themeStore.currentTheme.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("放大字体 (⌘+)") { themeStore.zoomIn() }
                    Button("缩小字体 (⌘-)") { themeStore.zoomOut() }
                    Button("重置默认字号 (13pt)") { themeStore.resetZoom() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 11))
                        Text(themeStore.currentTheme.name.components(separatedBy: " ").first ?? "主题")
                            .font(.caption)
                    }
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .help("切换终端配色与字体大小")
                
                Divider()
                    .frame(height: 14)
                
                // Split Mode Capsule Controller
                HStack(spacing: 2) {
                    Button(action: {
                        toggleSplitMode(to: .horizontal)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 11))
                            Text("左右")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(isSplit && splitOrientation == .horizontal ? .white : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(isSplit && splitOrientation == .horizontal ? Color.accentColor : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("左右并排分屏 (再次点击还原单屏)")
                    
                    Button(action: {
                        toggleSplitMode(to: .vertical)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "rectangle.split.1x2")
                                .font(.system(size: 11))
                            Text("上下")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(isSplit && splitOrientation == .vertical ? .white : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(isSplit && splitOrientation == .vertical ? Color.accentColor : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("上下堆叠分屏 (再次点击还原单屏)")
                }
                .padding(2)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Interactive Search & Highlight Bar (with Prominent Red Theme)
            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.red)
                    
                    TextField("输入关键字实时搜索与红色高亮 (Enter 下一个)...", text: $searchText)
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
                        HStack(spacing: 4) {
                            Circle()
                                .fill(searchTotal > 0 ? Color.red : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(searchTotal > 0 ? "\(searchIndex)/\(searchTotal) 处匹配" : "无匹配项")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(searchTotal > 0 ? .white : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(searchTotal > 0 ? Color.red : Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                        .shadow(color: searchTotal > 0 ? Color.red.opacity(0.4) : Color.clear, radius: 4)
                    }
                    
                    Button(action: {
                        isCaseSensitive.toggle()
                        updateSearch()
                    }) {
                        Text("Aa")
                            .font(.system(size: 11, weight: isCaseSensitive ? .bold : .regular))
                            .foregroundColor(isCaseSensitive ? .red : .secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isCaseSensitive ? Color.red.opacity(0.15) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("区分大小写")
                    
                    Button(action: findPrevious) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(searchTotal == 0)
                    .help("查找上一个")
                    
                    Button(action: findNext) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
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
                    }
                    .buttonStyle(.plain)
                    .help("关闭搜索 (ESC)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(height: 1.5)
                        .foregroundColor(Color.red.opacity(0.8)),
                    alignment: .bottom
                )
                Divider()
            }
            
            Divider()
            
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
                TerminalErrorDetector.shared.onErrorDetected = { event in
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
        DispatchQueue.main.async {
            if paneIndex == 1 {
                if let pt = primaryTerminal {
                    pt.window?.makeFirstResponder(pt)
                }
            } else {
                if let st = secondaryTerminal {
                    st.window?.makeFirstResponder(st)
                }
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
                    // Active Status Dot & Pane Name
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
                        // Quick Switch Secondary Session Dropdown Menu
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
            
            // Persistent Terminal Instance Representation
            TerminalContainerView(
                session: targetSession,
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
                    } else {
                        self.secondaryTerminal = term
                    }
                },
                onFocused: {
                    self.activePane = paneIndex
                }
            )
            .opacity(isSplit && !isFocused ? 0.88 : 1.0)
        }
        .overlay(
            isSplit ? RoundedRectangle(cornerRadius: 0)
                .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isFocused ? 2.0 : 1.0) : nil
        )
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
