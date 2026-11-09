import SwiftUI
import UniformTypeIdentifiers

public struct TerminalSplitView: View {
    @ObservedObject private var themeStore: ThemeStore = .shared
    
    public let tabId: UUID
    let session: SessionItem
    let onDirectoryChanged: ((String) -> Void)?
    let onTerminalReady: ((CustomTerminalView) -> Void)?
    let onActiveTerminalChanged: ((CustomTerminalView) -> Void)?
    let onDiagnoseRequested: ((String) -> Void)?
    
    // Search state
    @State private var showSearch: Bool = false
    @State private var searchText: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var searchIndex: Int = 0
    @State private var searchTotal: Int = 0
    
    @State private var isDropTarget: Bool = false
    @State private var currentPath: String = "~"
    
    // Persistent Terminal instance
    @State private var terminal: CustomTerminalView?
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
    
    public var body: some View {
        VStack(spacing: 0) {
            // Interactive Search & Highlight Bar
            if showSearch {
                searchBarView
            }
            
            // Dedicated Serial Engineering Quick Action Bar (Only for serial protocol)
            if session.protocolType == .serial {
                serialActionBarView
            }
            
            // Terminal Main Area (with Drag & Drop upload support)
            ZStack {
                TerminalContainerView(
                    session: session,
                    tabId: tabId,
                    theme: themeStore.currentTheme,
                    fontSize: themeStore.fontSize,
                    existingTerminal: terminal,
                    onDirectoryChanged: { dir in
                        self.currentPath = dir
                        self.onDirectoryChanged?(dir)
                    },
                    onTerminalReady: { term in
                        self.terminal = term
                        self.onTerminalReady?(term)
                        self.onActiveTerminalChanged?(term)
                    },
                    onFocused: {
                        if let t = self.terminal {
                            self.onActiveTerminalChanged?(t)
                        }
                    }
                )
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .background(Color(themeStore.currentTheme.backgroundColor))
                
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
                    errorNotificationToast(event: event)
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
                            terminal?.handleDroppedFile(url: fileUrl)
                        }
                    }
                }
                return true
            }
        }
    }
    
    // MARK: - Search Bar View
    private var searchBarView: some View {
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
                terminal?.clearSearch()
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
    
    // MARK: - Serial Engineering Action Bar
    private var serialActionBarView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text("串口硬件调测:")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.secondary)
            
            Button(action: {
                terminal?.sendWakeupKeys()
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
                terminal?.sendStopAutoboot()
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
                terminal?.sendBreakSignal()
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
    
    // MARK: - Floating Error Diagnosis Toast
    private func errorNotificationToast(event: DetectedErrorEvent) -> some View {
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
                            .lineLimit(1)
                        Text(event.summary)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 240, alignment: .leading)
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
                        .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .fixedSize()
                    
                    Button(action: {
                        withAnimation { activeErrorEvent = nil }
                    }) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
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
    
    // MARK: - Search Operations
    private func updateSearch() {
        guard let t = terminal else { return }
        let res = t.performSearch(query: searchText, caseSensitive: isCaseSensitive)
        self.searchIndex = res.index
        self.searchTotal = res.total
    }
    
    private func findNext() {
        guard let t = terminal else { return }
        let res = t.findNextMatch(query: searchText, caseSensitive: isCaseSensitive)
        self.searchIndex = res.index
        self.searchTotal = res.total
    }
    
    private func findPrevious() {
        guard let t = terminal else { return }
        let res = t.findPreviousMatch(query: searchText, caseSensitive: isCaseSensitive)
        self.searchIndex = res.index
        self.searchTotal = res.total
    }
}
