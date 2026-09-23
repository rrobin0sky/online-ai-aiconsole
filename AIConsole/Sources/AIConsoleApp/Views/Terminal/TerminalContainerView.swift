import SwiftUI
import AppKit
import SwiftTerm

public struct TerminalContainerView: NSViewRepresentable {
    public let session: SessionItem
    public let theme: TerminalTheme
    public let fontSize: CGFloat
    public var existingTerminal: CustomTerminalView?
    public let onDirectoryChanged: ((String) -> Void)?
    public let onTerminalReady: ((CustomTerminalView) -> Void)?
    public var onFocused: (() -> Void)?
    
    public init(
        session: SessionItem,
        theme: TerminalTheme = .defaultTheme,
        fontSize: CGFloat = 13.0,
        existingTerminal: CustomTerminalView? = nil,
        onDirectoryChanged: ((String) -> Void)? = nil,
        onTerminalReady: ((CustomTerminalView) -> Void)? = nil,
        onFocused: (() -> Void)? = nil
    ) {
        self.session = session
        self.theme = theme
        self.fontSize = fontSize
        self.existingTerminal = existingTerminal
        self.onDirectoryChanged = onDirectoryChanged
        self.onTerminalReady = onTerminalReady
        self.onFocused = onFocused
    }
    
    public func makeNSView(context: Context) -> CustomTerminalView {
        if let existing = existingTerminal {
            existing.applyTheme(theme)
            existing.applyFontSize(fontSize)
            existing.onDirectoryChanged = onDirectoryChanged
            existing.onFocused = onFocused
            DispatchQueue.main.async {
                onTerminalReady?(existing)
            }
            return existing
        }
        let terminalView = CustomTerminalView(frame: .zero)
        terminalView.applyTheme(theme)
        terminalView.applyFontSize(fontSize)
        terminalView.onDirectoryChanged = onDirectoryChanged
        terminalView.onFocused = onFocused
        terminalView.startSession(session: session)
        DispatchQueue.main.async {
            onTerminalReady?(terminalView)
        }
        return terminalView
    }
    
    public func updateNSView(_ nsView: CustomTerminalView, context: Context) {
        nsView.applyTheme(theme)
        nsView.applyFontSize(fontSize)
        nsView.onDirectoryChanged = onDirectoryChanged
        nsView.onFocused = onFocused
        DispatchQueue.main.async {
            onTerminalReady?(nsView)
        }
    }
}

final class ProcessDelegateBridge: NSObject, LocalProcessTerminalViewDelegate {
    weak var target: CustomTerminalView?
    
    init(target: CustomTerminalView) {
        self.target = target
    }
    
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let dir = directory {
            var path = dir
            if path.hasPrefix("file://"), let url = URL(string: path) {
                path = url.path
            }
            target?.currentWorkingDirectory = path
            DispatchQueue.main.async { [weak self] in
                self?.target?.onDirectoryChanged?(path)
            }
        }
    }
    
    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}

public final class CustomTerminalView: LocalProcessTerminalView {
    public var currentSession: SessionItem?
    public var isRecording: Bool = false
    public var recordedTranscript: [String] = []
    public var currentWorkingDirectory: String = "~"
    public var onDirectoryChanged: ((String) -> Void)?
    public var onFocused: (() -> Void)?
    
    public var recordingFileURL: URL?
    private var recordingFileHandle: FileHandle?
    
    private var sessionHistoryRing: [String] = []
    private let maxHistoryChunks = 2000
    private var delegateBridge: ProcessDelegateBridge?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupDelegateBridge()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDelegateBridge()
    }
    
    public override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        self.onFocused?()
        super.mouseDown(with: event)
    }
    
    private func setupDelegateBridge() {
        let bridge = ProcessDelegateBridge(target: self)
        self.delegateBridge = bridge
        self.processDelegate = bridge
    }
    
    private var lastPasswordInjectTime: Date = Date.distantPast
    private var passwordInjectCount: Int = 0
    
    public override func dataReceived(slice: ArraySlice<UInt8>) {
        let rawText = String(decoding: slice, as: UTF8.self)
        
        // 0. Continuous Full History Capture for AI Diagnosis (Beyond screen size)
        if !rawText.isEmpty {
            if sessionHistoryRing.count >= maxHistoryChunks {
                sessionHistoryRing.removeFirst(100)
            }
            sessionHistoryRing.append(rawText)
        }
        
        // 1. Realtime Crash-Proof Session Recording Streamed to Disk
        if isRecording, let handle = recordingFileHandle, let data = rawText.data(using: .utf8) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.synchronize()
            recordedTranscript.append(rawText)
        }
        
        // 2. Realtime AI Error & Anomaly Detection
        if !rawText.isEmpty {
            TerminalErrorDetector.shared.processOutput(chunk: rawText) { [weak self] in
                self?.extractRecentBuffer(maxLines: 80) ?? ""
            }
        }
        
        // 3. Smart SSH / Sudo Password Auto-Injection from Keychain
        if let session = currentSession, !rawText.isEmpty {
            handleAutoPasswordInjection(session: session, incomingText: rawText)
        }
        
        feed(byteArray: slice)
    }
    
    private func handleAutoPasswordInjection(session: SessionItem, incomingText: String) {
        let lower = incomingText.lowercased()
        let isPasswordPrompt = lower.hasSuffix("password:") ||
                               lower.hasSuffix("password: ") ||
                               lower.contains("password for ")
        
        let isPassphrasePrompt = lower.contains("enter passphrase for key") ||
                                 lower.contains("passphrase for ") ||
                                 lower.hasSuffix("passphrase:") ||
                                 lower.hasSuffix("passphrase: ")
        
        guard isPasswordPrompt || isPassphrasePrompt else { return }
        
        let now = Date()
        if now.timeIntervalSince(lastPasswordInjectTime) < 5.0 && passwordInjectCount >= 3 {
            return
        }
        
        var targetSecret: String?
        if isPassphrasePrompt, let pKey = session.passphraseKey {
            targetSecret = KeychainHelper.shared.read(key: pKey)
        }
        if targetSecret == nil || targetSecret?.isEmpty == true {
            targetSecret = KeychainHelper.shared.read(key: session.credentialKey)
        }
        
        if let secret = targetSecret, !secret.isEmpty {
            lastPasswordInjectTime = now
            passwordInjectCount += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                var payload = secret
                if !payload.hasSuffix("\n") { payload += "\n" }
                if let data = payload.data(using: .utf8) {
                    let bytes = [UInt8](data)
                    self.send(data: bytes[...])
                }
            }
        }
    }
    
    public func startSession(session: SessionItem) {
        self.currentSession = session
        
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let initialDir = (session.initialDirectory?.isEmpty == false)
            ? session.initialDirectory!.replacingOccurrences(of: "~", with: homePath)
            : homePath
        FileManager.default.changeCurrentDirectoryPath(initialDir)
        
        // Prepare login environment variables
        var env: [String] = []
        for (k, v) in ProcessInfo.processInfo.environment {
            env.append("\(k)=\(v)")
        }
        if !env.contains(where: { $0.hasPrefix("TERM=") }) {
            env.append("TERM=xterm-256color")
        }
        if !env.contains(where: { $0.hasPrefix("LANG=") }) {
            env.append("LANG=zh_CN.UTF-8")
        }
        if !env.contains(where: { $0.hasPrefix("HOME=") }) {
            env.append("HOME=\(homePath)")
        }
        
        // Display Startup Banner
        let banner = SessionBannerService.shared.generateStartupBanner(for: session)
        if let bData = banner.data(using: .utf8) {
            let bytes = [UInt8](bData)
            feed(byteArray: bytes[...])
        }
        
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        if session.protocolType == .local {
            let targetShell = (session.startupCommand?.isEmpty == false) ? session.startupCommand! : shell
            startProcess(executable: targetShell, args: ["-l"], environment: env, execName: "-zsh")
        } else if session.host == "localhost" || session.host == "127.0.0.1" && session.protocolType != .ssh {
            startProcess(executable: shell, args: ["-l"], environment: env, execName: "-zsh")
        } else if session.protocolType == .ssh {
            var args: [String] = []
            
            // Port
            args.append(contentsOf: ["-p", "\(session.port)"])
            
            // Universal Seamless Compatibility (Zero-Config support for Cisco, Huawei, H3C, Linux, BMC & modern servers)
            args.append(contentsOf: [
                "-o", "HostKeyAlgorithms=+ssh-rsa",
                "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
                "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa",
                "-o", "KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1",
                "-o", "Ciphers=+aes128-cbc,3des-cbc,aes192-cbc,aes256-cbc",
                "-o", "MACs=+hmac-sha1,hmac-sha1-96,hmac-md5",
                "-o", "StrictHostKeyChecking=accept-new"
            ])
            
            // Server Alive Interval
            if session.keepAliveInterval > 0 {
                args.append(contentsOf: ["-o", "ServerAliveInterval=\(session.keepAliveInterval)"])
                args.append(contentsOf: ["-o", "ServerAliveCountMax=3"])
            }
            
            // ProxyJump (Jump host)
            if let jump = session.proxyJump, !jump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                args.append(contentsOf: ["-J", jump.trimmingCharacters(in: .whitespacesAndNewlines)])
            }
            
            // Private Key
            if let keyPath = session.privateKeyPath, !keyPath.isEmpty {
                args.append(contentsOf: ["-i", keyPath])
            }
            
            // Port forwarding tunnels
            if let tunnelRules = session.portForwardingRules, !tunnelRules.isEmpty {
                let ruleTokens = tunnelRules.split(separator: " ").map(String.init)
                args.append(contentsOf: ruleTokens)
            }
            
            // Remote target user@host
            let remoteTarget = "\(session.username)@\(session.host)"
            args.append(remoteTarget)
            
            // Initial directory or startup command if provided
            if let initDir = session.initialDirectory, !initDir.isEmpty {
                let remoteCmd = "cd \(initDir) && exec $SHELL -l"
                args.append(contentsOf: ["-t", remoteCmd])
            } else if let startupCmd = session.startupCommand, !startupCmd.isEmpty {
                args.append(contentsOf: ["-t", startupCmd])
            }
            
            startProcess(executable: "/usr/bin/ssh", args: args, environment: env, execName: "ssh")
        } else if session.protocolType == .telnet {
            startProcess(executable: "/usr/bin/telnet", args: [session.host, "\(session.port)"], environment: env, execName: "telnet")
        } else if session.protocolType == .serial {
            if let dev = session.serialDevicePath {
                startProcess(executable: "/usr/bin/screen", args: [dev, "\(session.baudRate)"], environment: env, execName: "screen")
            } else {
                startProcess(executable: shell, args: ["-l"], environment: env, execName: "-zsh")
            }
        } else if session.protocolType == .ble {
            let bleNotice = "\r\n\u{001B}[36m[BLE]\u{001B}[0m 正在扫描并连接低功耗蓝牙设备: \(session.bleDeviceName ?? "未指定")...\r\n\u{001B}[33m[BLE]\u{001B}[0m 服务 UUID: \(session.bleServiceUUID ?? "默认") | MTU: \(session.bleMtu)\r\n\r\n"
            if let nData = bleNotice.data(using: .utf8) {
                feed(byteArray: [UInt8](nData)[...])
            }
            startProcess(executable: shell, args: ["-l"], environment: env, execName: "-zsh")
        } else {
            startProcess(executable: shell, args: ["-l"], environment: env, execName: "-zsh")
        }
    }
    
    public func handleDroppedFile(url: URL) {
        let filePath = url.path
        let escaped = filePath.replacingOccurrences(of: " ", with: "\\ ")
        sendCommand(command: escaped, autoExecute: false)
    }
    
    public func applyTheme(_ theme: TerminalTheme) {
        self.nativeBackgroundColor = theme.backgroundColor
        self.nativeForegroundColor = theme.foregroundColor
        self.caretColor = theme.cursorColor
        
        var colors: [SwiftTerm.Color] = []
        for hex in theme.ansiHexColors {
            let ns = NSColor(hex: hex)
            let color = SwiftTerm.Color(
                red: UInt16(ns.redComponent * 65535.0),
                green: UInt16(ns.greenComponent * 65535.0),
                blue: UInt16(ns.blueComponent * 65535.0)
            )
            colors.append(color)
        }
        if colors.count >= 16 {
            self.installColors(colors)
        }
        
        // Prominent Red Highlight for Search Matches & Selection
        self.selectedTextBackgroundColor = NSColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 0.55)
    }
    
    public func applyFontSize(_ size: CGFloat) {
        if let customFont = NSFont(name: "SF Mono", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as NSFont? {
            self.font = customFont
        }
    }
    
    // MARK: - Search Support
    
    @discardableResult
    public func performSearch(query: String, caseSensitive: Bool = false) -> (index: Int, total: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearSearch()
            return (0, 0)
        }
        let opts = SearchOptions(caseSensitive: caseSensitive)
        // Keep focus on input field while searching live
        findNext(trimmed, options: opts, scrollToResult: false)
        return searchMatchSummary(trimmed, options: opts)
    }
    
    @discardableResult
    public func findNextMatch(query: String, caseSensitive: Bool = false) -> (index: Int, total: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }
        let opts = SearchOptions(caseSensitive: caseSensitive)
        findNext(trimmed, options: opts, scrollToResult: true)
        return searchMatchSummary(trimmed, options: opts)
    }
    
    @discardableResult
    public func findPreviousMatch(query: String, caseSensitive: Bool = false) -> (index: Int, total: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }
        let opts = SearchOptions(caseSensitive: caseSensitive)
        findPrevious(trimmed, options: opts, scrollToResult: true)
        return searchMatchSummary(trimmed, options: opts)
    }
    
    // MARK: - Crash-Proof Realtime Recording & Exporting
    
    public func startRecording(sessionName: String, completion: @escaping (Bool, URL?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.title = "选择会话日志实时保存位置 (防死机实时写入)"
        savePanel.prompt = "开始实时录制"
        savePanel.allowedContentTypes = [.plainText]
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeName = sessionName.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "-")
        savePanel.nameFieldStringValue = "AIConsole-\(safeName)-\(formatter.string(from: Date())).log"
        
        let targetWindow = self.window ?? NSApp.keyWindow ?? NSApp.mainWindow
        
        let onChosenURL: (URL) -> Void = { [weak self] url in
            guard let self = self else { return }
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                
                let headerFormatter = DateFormatter()
                headerFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                var headerText = "====================================================\n"
                headerText += " AIConsole 终端实时审计日志 (Crash-Proof)\n"
                headerText += " 会话名称: \(self.currentSession?.name ?? sessionName)\n"
                headerText += " 协议类型: \(self.currentSession?.protocolType.rawValue ?? "SSH")\n"
                headerText += " 主机/地址: \(self.currentSession?.host ?? ""):\(self.currentSession?.port ?? 22)\n"
                headerText += " 当前目录: \(self.currentWorkingDirectory)\n"
                headerText += " 开始录制时间: \(headerFormatter.string(from: Date()))\n"
                headerText += "====================================================\n\n"
                
                if let headerData = headerText.data(using: .utf8) {
                    handle.write(headerData)
                    handle.synchronizeFile()
                }
                
                self.recordingFileHandle = handle
                self.recordingFileURL = url
                self.isRecording = true
                completion(true, url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "无法创建日志文件"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
                completion(false, nil)
            }
        }
        
        if let win = targetWindow {
            savePanel.beginSheetModal(for: win) { response in
                if response == .OK, let url = savePanel.url {
                    onChosenURL(url)
                } else {
                    completion(false, nil)
                }
            }
        } else {
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    onChosenURL(url)
                } else {
                    completion(false, nil)
                }
            }
        }
    }
    
    public func stopRecording() -> URL? {
        guard isRecording, let handle = recordingFileHandle, let url = recordingFileURL else {
            isRecording = false
            return nil
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let footerText = "\n\n=== ⏹ 结束会话录制 [\(formatter.string(from: Date()))] ===\n"
        if let footerData = footerText.data(using: .utf8) {
            handle.write(footerData)
            handle.synchronizeFile()
        }
        
        try? handle.close()
        self.recordingFileHandle = nil
        self.isRecording = false
        
        // Auto locate in Finder
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }
    
    public func extractFullTranscript() -> String {
        var text = ""
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        text += "====================================================\n"
        text += " AIConsole 终端会话记录 (NetOps Pro)\n"
        text += " 会话名称: \(currentSession?.name ?? "未知会话")\n"
        text += " 协议类型: \(currentSession?.protocolType.rawValue ?? "SSH")\n"
        text += " 主机/地址: \(currentSession?.host ?? ""):\(currentSession?.port ?? 22)\n"
        text += " 当前工作目录: \(currentWorkingDirectory)\n"
        text += " 导出时间: \(formatter.string(from: Date()))\n"
        text += "====================================================\n\n"
        
        if !recordedTranscript.isEmpty {
            text += "--- [实时录制内容与交互] ---\n"
            text += recordedTranscript.joined() + "\n\n"
        }
        
        text += "--- [终端屏幕完整输出缓冲区] ---\n"
        let totalRows = self.getTerminal().rows
        for r in 0..<totalRows {
            if let line = self.getTerminal().getLine(row: r) {
                let str = line.translateToString(trimRight: true)
                text += str + "\n"
            }
        }
        return text
    }
    
    public func extractRecentBuffer(maxLines: Int = 500) -> String {
        // 1. Primary: Extract from full multi-page stream history
        if !sessionHistoryRing.isEmpty {
            let combined = sessionHistoryRing.joined()
            // Clean ANSI escape sequences
            let cleanText = combined.replacingOccurrences(
                of: "\\x1b\\[[0-9;]*[a-zA-Z]",
                with: "",
                options: .regularExpression
            )
            let lines = cleanText.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            if !lines.isEmpty {
                let tailLines = lines.suffix(maxLines)
                return tailLines.joined(separator: "\n")
            }
        }
        
        // 2. Fallback: Extract from visible rows
        var text = ""
        let totalRows = self.getTerminal().rows
        let startRow = max(0, totalRows - min(maxLines, totalRows))
        for r in startRow..<totalRows {
            if let line = self.getTerminal().getLine(row: r) {
                let str = line.translateToString(trimRight: true)
                if !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text += str + "\n"
                }
            }
        }
        return text.isEmpty ? "终端已就绪。" : text
    }
    
    public func sendBroadcastCharacters(_ characters: String) {
        if let data = characters.data(using: .utf8) {
            let bytes = [UInt8](data)
            self.send(data: bytes[...])
        }
    }
    
    public func sendBroadcastData(_ data: Data) {
        let bytes = [UInt8](data)
        self.send(data: bytes[...])
    }
    
    public func sendCommand(command: String, autoExecute: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
        
        var toSend = command
        if autoExecute && !toSend.hasSuffix("\n") {
            toSend += "\n"
        }
        
        if isRecording {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            recordedTranscript.append("[\(formatter.string(from: Date())) INPUT] > \(command)\(autoExecute ? "\n" : "")")
        }
        
        if let data = toSend.data(using: .utf8) {
            let bytes = [UInt8](data)
            self.send(data: bytes[...])
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }
}
