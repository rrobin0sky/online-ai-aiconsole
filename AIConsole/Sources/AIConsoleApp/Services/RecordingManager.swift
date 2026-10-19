import Foundation
import Combine
import AppKit

public struct ActiveRecordingState: Identifiable {
    public let id: UUID // Tab ID
    public let sessionName: String
    public let fileURL: URL
    public let fileHandle: FileHandle
    public let startedAt: Date
    public var lineCount: Int
    public var byteCount: Int
    public var recentTranscript: [String]
}

@MainActor
public final class RecordingManager: ObservableObject {
    public static let shared = RecordingManager()
    
    @Published public private(set) var activeRecordings: [UUID: ActiveRecordingState] = [:]
    @Published public var includeTimestamps: Bool = true
    
    private let maxRecentTranscriptLines = 600
    private let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()
    
    private init() {}
    
    public func isRecording(tabId: UUID) -> Bool {
        activeRecordings[tabId] != nil
    }
    
    public func recordingState(for tabId: UUID) -> ActiveRecordingState? {
        activeRecordings[tabId]
    }
    
    public func elapsedTimeString(for tabId: UUID) -> String {
        guard let state = activeRecordings[tabId] else { return "00:00" }
        let diff = max(0, Int(Date().timeIntervalSince(state.startedAt)))
        let m = diff / 60
        let s = diff % 60
        if m < 60 {
            return String(format: "%02d:%02d", m, s)
        } else {
            let h = m / 60
            let remM = m % 60
            return String(format: "%02d:%02d:%02d", h, remM, s)
        }
    }
    
    public func startRecording(
        tabId: UUID,
        sessionName: String,
        targetWindow: NSWindow?,
        initialMetadata: [String: String] = [:],
        completion: @escaping (Bool, URL?) -> Void
    ) {
        if isRecording(tabId: tabId) {
            completion(true, activeRecordings[tabId]?.fileURL)
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = "选择实时会话审计日志保存路径"
        savePanel.prompt = "开启实时审计"
        savePanel.allowedContentTypes = [.plainText]
        
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let safeName = sessionName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        savePanel.nameFieldStringValue = "AIConsole-\(safeName)-\(df.string(from: Date())).log"
        
        let onChosenURL: (URL) -> Void = { [weak self] url in
            guard let self = self else { return }
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                
                let headerDf = DateFormatter()
                headerDf.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                var header = "====================================================\n"
                header += " AIConsole 终端实时审计日志 (Crash-Proof Recording)\n"
                header += " 会话名称: \(sessionName)\n"
                for (k, v) in initialMetadata {
                    header += " \(k): \(v)\n"
                }
                header += " 开启时间: \(headerDf.string(from: Date()))\n"
                header += " 审计机制: 实时落盘流式写入 (防异常退出数据丢失)\n"
                header += "====================================================\n\n"
                
                if let hData = header.data(using: .utf8) {
                    try handle.write(contentsOf: hData)
                    try handle.synchronize()
                }
                
                let state = ActiveRecordingState(
                    id: tabId,
                    sessionName: sessionName,
                    fileURL: url,
                    fileHandle: handle,
                    startedAt: Date(),
                    lineCount: 0,
                    byteCount: 0,
                    recentTranscript: []
                )
                
                self.activeRecordings[tabId] = state
                HapticFeedbackHelper.shared.performAlignment()
                completion(true, url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "无法创建录制文件"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
                completion(false, nil)
            }
        }
        
        let win = targetWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let win = win {
            savePanel.beginSheetModal(for: win) { resp in
                if resp == .OK, let url = savePanel.url {
                    onChosenURL(url)
                } else {
                    completion(false, nil)
                }
            }
        } else {
            savePanel.begin { resp in
                if resp == .OK, let url = savePanel.url {
                    onChosenURL(url)
                } else {
                    completion(false, nil)
                }
            }
        }
    }
    
    public func appendChunk(tabId: UUID, rawChunk: String) {
        guard var state = activeRecordings[tabId] else { return }
        let cleaned = TerminalTextSanitizer.clean(rawChunk)
        guard !cleaned.isEmpty else { return }
        
        var toWrite = cleaned
        if includeTimestamps {
            let stamp = "[\(timestampFormatter.string(from: Date()))] "
            let lines = cleaned.components(separatedBy: "\n")
            toWrite = lines.map { $0.isEmpty ? "" : "\(stamp)\($0)" }.joined(separator: "\n")
        }
        
        if let data = toWrite.data(using: .utf8) {
            _ = try? state.fileHandle.seekToEnd()
            try? state.fileHandle.write(contentsOf: data)
            try? state.fileHandle.synchronize()
            state.byteCount += data.count
        }
        
        let newLines = cleaned.components(separatedBy: "\n")
        state.lineCount += max(1, newLines.count - 1)
        state.recentTranscript.append(contentsOf: newLines)
        if state.recentTranscript.count > maxRecentTranscriptLines {
            state.recentTranscript.removeFirst(state.recentTranscript.count - maxRecentTranscriptLines)
        }
        
        activeRecordings[tabId] = state
    }
    
    @discardableResult
    public func stopRecording(tabId: UUID) -> URL? {
        guard let state = activeRecordings.removeValue(forKey: tabId) else { return nil }
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let footer = "\n\n=== ⏹ 结束会话录制 [\(df.string(from: Date()))] (共写入 \(state.lineCount) 行) ===\n"
        if let fData = footer.data(using: .utf8) {
            try? state.fileHandle.write(contentsOf: fData)
            try? state.fileHandle.synchronize()
        }
        
        try? state.fileHandle.close()
        HapticFeedbackHelper.shared.performGeneric()
        return state.fileURL
    }
    
    public func stopAllRecordings() {
        let keys = Array(activeRecordings.keys)
        for key in keys {
            stopRecording(tabId: key)
        }
    }
}
