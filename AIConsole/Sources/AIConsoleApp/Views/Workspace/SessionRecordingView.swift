import SwiftUI
import AppKit

public struct SessionRecordingView: View {
    public let activeTerminalGetter: () -> CustomTerminalView?
    public let currentSession: SessionItem?
    public let activeTabId: UUID?
    
    @ObservedObject private var recordingManager = RecordingManager.shared
    @State private var autoScrollToBottom: Bool = true
    @State private var copiedToast: Bool = false
    @State private var previewTargetTabId: UUID?
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    public init(
        activeTerminalGetter: @escaping () -> CustomTerminalView?,
        currentSession: SessionItem?,
        activeTabId: UUID? = nil
    ) {
        self.activeTerminalGetter = activeTerminalGetter
        self.currentSession = currentSession
        self.activeTabId = activeTabId
    }
    
    private var effectiveTabId: UUID? {
        previewTargetTabId ?? activeTabId
    }
    
    private var currentState: ActiveRecordingState? {
        guard let tid = effectiveTabId else { return nil }
        return recordingManager.recordingState(for: tid)
    }
    
    private var isCurrentlyRecording: Bool {
        guard let tid = effectiveTabId else { return false }
        return recordingManager.isRecording(tabId: tid)
    }
    
    private var recordedText: String {
        guard let state = currentState else { return "" }
        return state.recentTranscript.joined(separator: "\n")
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Stats & Session Target
            VStack(spacing: 8) {
                // Multi-Recording Switcher (If multiple tabs are recording)
                let allActive = Array(recordingManager.activeRecordings.values)
                if allActive.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "recordingtape")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                        Text("多会话录制中心 (共 \(allActive.count) 个后台录制):")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Menu {
                            ForEach(allActive) { rec in
                                Button(action: {
                                    previewTargetTabId = rec.id
                                }) {
                                    HStack {
                                        Text("\(rec.sessionName) (\(recordingManager.elapsedTimeString(for: rec.id)))")
                                        if rec.id == effectiveTabId {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(currentState?.sessionName ?? "切换查看")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
                
                HStack {
                    HStack(spacing: 6) {
                        if isCurrentlyRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("正在实时流式录制")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.red)
                            
                            if let tid = effectiveTabId {
                                Text("(\(recordingManager.elapsedTimeString(for: tid)))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text("当前会话未录制")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if let sess = currentSession {
                        Text(sess.name)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                
                // Action Buttons Bar
                HStack(spacing: 8) {
                    if isCurrentlyRecording {
                        Button(action: stopCurrentRecording) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.circle.fill")
                                Text("停止录制")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        if let url = currentState?.fileURL {
                            Button(action: {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "folder")
                                    Text("在访达中定位")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("在访达 Finder 中打开保存的 .log 文件")
                        }
                    } else {
                        Button(action: startCurrentRecording) {
                            HStack(spacing: 4) {
                                Image(systemName: "record.circle")
                                    .foregroundColor(.red)
                                Text("开始实时录制")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("选择文件保存路径并开启防死机实时流式录制")
                    }
                    
                    Spacer()
                    
                    // Copy button
                    Button(action: copyRecordedContent) {
                        HStack(spacing: 3) {
                            Image(systemName: copiedToast ? "checkmark" : "doc.on.doc")
                            Text(copiedToast ? "已复制" : "复制")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(recordedText.isEmpty)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Live Recorded Content Scroll Area
            if recordedText.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "recordingtape")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Text("暂无录制内容")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("点击上方「开始实时录制」按钮，终端产生的所有输入与输出都将实时显示在此处，并防死机写入本地 .log 文件。\n支持多 Tab 并发独立录制与毫秒级时间戳注入。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(recordedText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                            .id("bottom")
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .onChange(of: recordedText) { _, _ in
                        if autoScrollToBottom {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Bottom Info Bar
            HStack {
                if let st = currentState {
                    Text("\(st.lineCount) 行 • \(st.byteCount) 字节")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("0 行 • 0 字节")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("毫秒时间戳", isOn: $recordingManager.includeTimestamps)
                    .font(.caption2)
                    .toggleStyle(.checkbox)
                    .help("在每行日志开头注入 [yyyy-MM-dd HH:mm:ss.SSS] 精准时间戳")
                
                Toggle("自动滚底", isOn: $autoScrollToBottom)
                    .font(.caption2)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onReceive(timer) { _ in
            // Trigger UI refresh for elapsed time
        }
        .onChange(of: activeTabId) { _, newTabId in
            // When switching tabs, reset custom target preview unless explicitly pinned
            previewTargetTabId = nil
        }
    }
    
    private func startCurrentRecording() {
        guard let tid = effectiveTabId else { return }
        let sessionName = currentSession?.name ?? "Terminal"
        let term = activeTerminalGetter()
        
        var meta: [String: String] = [:]
        if let s = currentSession {
            meta["协议类型"] = s.protocolType.rawValue
            meta["主机地址"] = "\(s.host):\(s.port)"
        }
        if let dir = term?.currentWorkingDirectory {
            meta["当前目录"] = dir
        }
        
        recordingManager.startRecording(
            tabId: tid,
            sessionName: sessionName,
            targetWindow: term?.window,
            initialMetadata: meta
        ) { started, url in
            // State updated in RecordingManager
        }
    }
    
    private func stopCurrentRecording() {
        guard let tid = effectiveTabId else { return }
        _ = recordingManager.stopRecording(tabId: tid)
    }
    
    private func copyRecordedContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recordedText, forType: .string)
        withAnimation { copiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { copiedToast = false }
        }
    }
}
