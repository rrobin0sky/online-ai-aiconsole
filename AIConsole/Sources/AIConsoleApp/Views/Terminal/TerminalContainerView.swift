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
        
        // 1. Realtime Crash-Proof Session Recording Streamed to Disk (Clean Human-Readable Text)
        if isRecording, let handle = recordingFileHandle {
            let cleaned = TerminalTextSanitizer.clean(rawText)
            if !cleaned.isEmpty {
                if let data = cleaned.data(using: .utf8) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.synchronize()
                }
                recordedTranscript.append(cleaned)
            }
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
        
        switch session.protocolType {
        case .local:
            let targetShell = (session.startupCommand?.isEmpty == false) ? session.startupCommand! : shell
            startProcess(executable: targetShell, args: ["-l"], environment: env, execName: "-zsh")
            
        case .serial:
            launchSerialProcess(session: session, environment: env)
            
        case .ssh:
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
            
        case .telnet:
            startProcess(executable: "/usr/bin/telnet", args: [session.host, "\(session.port)"], environment: env, execName: "telnet")
            
        case .ble:
            let bleNotice = "\r\n\u{001B}[36m[BLE]\u{001B}[0m 正在扫描并连接低功耗蓝牙设备: \(session.bleDeviceName ?? "未指定")...\r\n\u{001B}[33m[BLE]\u{001B}[0m 服务 UUID: \(session.bleServiceUUID ?? "默认") | MTU: \(session.bleMtu)\r\n\r\n"
            if let nData = bleNotice.data(using: .utf8) {
                feed(byteArray: [UInt8](nData)[...])
            }
            startProcess(executable: shell, args: ["-l"], environment: env, execName: "-zsh")
            
        default:
            startProcess(executable: shell, args: ["-l"], environment: env, execName: "-zsh")
        }
    }
    
    private func launchSerialProcess(session: SessionItem, environment: [String]) {
        let rawDev = session.serialDevicePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baud = session.baudRate > 0 ? session.baudRate : 9600
        
        // Find best available serial port if configured path doesn't exist
        var targetDev = rawDev
        if targetDev.isEmpty || !FileManager.default.fileExists(atPath: targetDev) {
            let available = (try? FileManager.default.contentsOfDirectory(atPath: "/dev"))?
                .filter { $0.hasPrefix("cu.") }
                .map { "/dev/\($0)" }
                .filter { $0.lowercased().contains("usb") || $0.lowercased().contains("wch") || $0.lowercased().contains("slab") } ?? []
            if let firstUSB = available.first {
                targetDev = firstUSB
            }
        }
        
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        let script = """
        DEV="\(targetDev)"
        BAUD="\(baud)"
        
        clear
        echo "\\033[36;1m[AIConsole 串口终端]\\033[0m 正在初始化硬件串口连接..."
        echo "设备路径: $DEV"
        echo "波特率: $BAUD bps (8-N-1)"
        echo "--------------------------------------------------------"
        
        if [ -z "$DEV" ] || [ ! -e "$DEV" ]; then
            echo "\\033[31;1m[❌ 错误] 未找到串口设备: $DEV\\033[0m"
            echo "请检查 USB-to-Console 数据线是否牢固插入 Mac。"
            echo "当前系统中检测到的可用串口设备:"
            ls -l /dev/cu.* 2>/dev/null || echo "无可用设备"
            echo "--------------------------------------------------------"
            echo "按回车键进入本地终端排查..."
            read -r
            exec "\(shell)" -l
        fi
        
        # 检查端口是否被外部程序独占占用 (例如 Stacio, screen, minicom 等)
        OCCUPIER=$(lsof "$DEV" 2>/dev/null | awk 'NR>1 {print $1, "(PID " $2 ")"}')
        if [ -n "$OCCUPIER" ]; then
            echo "\\033[31;1m[⚠️ 串口独占占用提示]\\033[0m 串口设备正被以下外部程序使用："
            echo "👉 \\033[33;1m$OCCUPIER\\033[0m"
            echo ""
            echo "在 macOS 系统中，串口同一时刻只允许一个应用打开独占访问。"
            echo "\\033[32;1m[快速解决办法]\\033[0m:"
            echo "  • 请彻底关闭该程序（如 Stacio、SecureCRT 等）；"
            echo "  • 或者输入 \\033[1;31mk\\033[0m 强行结束占用进程并立即连入串口。"
            echo "--------------------------------------------------------"
            echo -n "输入 'k' 强行释放端口并继续，或按回车进入排查模式: "
            read -r choice
            if [ "$choice" = "k" ] || [ "$choice" = "K" ]; then
                PIDS=$(lsof -t "$DEV" 2>/dev/null)
                if [ -n "$PIDS" ]; then
                    kill -9 $PIDS 2>/dev/null
                    sleep 0.5
                    echo "\\033[32m已成功释放串口，正在连入...\\033[0m"
                fi
            else
                exec "\(shell)" -l
            fi
        fi
        
        echo "\\033[32;1m[✅ 串口准备就绪]\\033[0m 正在接入设备控制台..."
        echo "\\033[33;1m[💡 重点提示]\\033[0m"
        echo "  • 连接 FortiGate 防火墙或 Cisco 交换机时，接入后请立刻按 \\033[1;4m1 ~ 2 次 [Enter/回车键]\\033[0m 唤醒登录提示符。"
        echo "  • 退出串口请按: \\033[1mCtrl + A\\033[0m 然后按 \\033[1mK\\033[0m (按 y 确认) 即可安全断开。"
        echo "--------------------------------------------------------"
        sleep 0.5
        exec /usr/bin/screen -fn "$DEV" "$BAUD"
        """
        
        startProcess(executable: "/bin/zsh", args: ["-c", script], environment: environment, execName: "serial-console")
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
                
                self.recordedTranscript.removeAll()
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
            let cleanText = TerminalTextSanitizer.clean(combined)
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
