import SwiftUI
import AppKit

public struct SessionRecordingView: View {
    public let activeTerminalGetter: () -> CustomTerminalView?
    public let currentSession: SessionItem?
    
    @State private var isRecording: Bool = false
    @State private var recordingFileURL: URL?
    @State private var recordedText: String = ""
    @State private var recordingStartTime: Date?
    @State private var elapsedTimeString: String = "00:00"
    @State private var autoScrollToBottom: Bool = true
    @State private var copiedToast: Bool = false
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    public init(
        activeTerminalGetter: @escaping () -> CustomTerminalView?,
        currentSession: SessionItem?
    ) {
        self.activeTerminalGetter = activeTerminalGetter
        self.currentSession = currentSession
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Stats & Session Target
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        if isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("正在实时录制")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.red)
                            
                            Text("(\(elapsedTimeString))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text("未录制")
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
                    if isRecording {
                        Button(action: stopRecording) {
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
                        
                        if let url = recordingFileURL {
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
                        Button(action: startRecording) {
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
                    
                    // Clear preview button
                    Button(action: {
                        recordedText = ""
                        activeTerminalGetter()?.recordedTranscript.removeAll()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(recordedText.isEmpty)
                    .help("清空当前实时预览（不会删除已写入磁盘的日志）")
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
                    
                    Text("点击上方「开始实时录制」按钮，终端产生的所有输入与输出都将实时显示在此处，并防死机写入本地 .log 文件。")
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
                Text("\(recordedText.components(separatedBy: "\n").count) 行 • \(recordedText.utf8.count) 字节")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle("自动滚至底部", isOn: $autoScrollToBottom)
                    .font(.caption2)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            syncStateFromTerminal()
        }
        .onReceive(timer) { _ in
            updateRecordingStateAndTimer()
        }
    }
    
    private func syncStateFromTerminal() {
        guard let term = activeTerminalGetter() else { return }
        self.isRecording = term.isRecording
        self.recordingFileURL = term.recordingFileURL
        if !term.recordedTranscript.isEmpty {
            self.recordedText = term.recordedTranscript.joined()
        }
    }
    
    private func updateRecordingStateAndTimer() {
        guard let term = activeTerminalGetter() else { return }
        self.isRecording = term.isRecording
        self.recordingFileURL = term.recordingFileURL
        
        // Sync live incoming transcript
        if !term.recordedTranscript.isEmpty {
            let full = term.recordedTranscript.joined()
            if full.count != self.recordedText.count {
                self.recordedText = full
            }
        }
        
        if isRecording {
            if recordingStartTime == nil {
                recordingStartTime = Date()
            }
            if let start = recordingStartTime {
                let diff = Int(Date().timeIntervalSince(start))
                let m = diff / 60
                let s = diff % 60
                elapsedTimeString = String(format: "%02d:%02d", m, s)
            }
        } else {
            recordingStartTime = nil
            elapsedTimeString = "00:00"
        }
    }
    
    private func startRecording() {
        guard let term = activeTerminalGetter() else { return }
        let sessionName = currentSession?.name ?? "Terminal"
        term.startRecording(sessionName: sessionName) { started, url in
            DispatchQueue.main.async {
                self.isRecording = started
                self.recordingFileURL = url
                if started {
                    self.recordingStartTime = Date()
                    self.recordedText = term.recordedTranscript.joined()
                }
            }
        }
    }
    
    private func stopRecording() {
        guard let term = activeTerminalGetter() else { return }
        let url = term.stopRecording()
        self.isRecording = false
        self.recordingFileURL = url
        self.recordingStartTime = nil
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
