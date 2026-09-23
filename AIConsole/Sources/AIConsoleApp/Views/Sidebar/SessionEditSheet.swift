import SwiftUI
import AppKit

public struct SessionEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sessionStore: SessionStore
    
    // Core Identification
    @State private var name: String
    @State private var isGroup: Bool
    @State private var protocolType: SessionProtocol
    @State private var selectedGroupId: UUID?
    @State private var colorHex: String
    
    // Active Tab in Right Form
    private enum ConfigTab: String, CaseIterable, Identifiable {
        case general = "常规连接"
        case advanced = "高级与终端"
        case network = "跳板机与隧道"
        
        var id: String { rawValue }
    }
    @State private var activeTab: ConfigTab = .general
    
    // Connection & Auth
    @State private var host: String
    @State private var port: Int
    @State private var username: String
    @State private var password: String = ""
    @State private var showPasswordPlain: Bool = false
    @State private var authMethod: String
    @State private var privateKeyPath: String
    @State private var passphrase: String = ""
    @State private var showPassphrasePlain: Bool = false
    
    // Advanced & Terminal Options
    @State private var terminalType: String
    @State private var keepAliveInterval: Int
    @State private var encoding: String
    @State private var initialDirectory: String
    @State private var startupCommand: String
    
    // Proxy & Tunnels
    @State private var proxyJump: String
    @State private var portForwardingRules: String
    
    // Serial Options
    @State private var serialDevicePath: String
    @State private var baudRate: Int
    @State private var dataBits: Int
    @State private var stopBits: Int
    @State private var parity: String
    @State private var flowControl: String
    @State private var detectedSerialPorts: [String] = []
    
    // BLE Options
    @State private var bleDeviceName: String
    @State private var bleServiceUUID: String
    @State private var bleCharacteristicUUID: String
    @State private var bleMtu: Int
    
    // SFTP & VNC
    @State private var sftpLocalPath: String
    @State private var sftpRemotePath: String
    @State private var sftpShowHidden: Bool
    @State private var vncColorDepth: Int
    @State private var vncViewOnly: Bool
    
    private let editingItem: SessionItem?
    private let parentGroupId: UUID?
    
    private let presetColors = [
        "#3B82F6", // Blue
        "#10B981", // Green
        "#F59E0B", // Orange
        "#EF4444", // Red
        "#8B5CF6", // Purple
        "#6B7280", // Gray
        "#00E5FF"  // Cyan
    ]
    
    private var availableGroups: [SessionItem] {
        sessionStore.rootItems.filter { $0.isGroup }
    }
    
    public init(sessionStore: SessionStore, editingItem: SessionItem? = nil, parentGroupId: UUID? = nil) {
        self.sessionStore = sessionStore
        self.editingItem = editingItem
        self.parentGroupId = parentGroupId
        
        _name = State(initialValue: editingItem?.name ?? "")
        _isGroup = State(initialValue: editingItem?.isGroup ?? false)
        _protocolType = State(initialValue: editingItem?.protocolType ?? .ssh)
        _host = State(initialValue: editingItem?.host ?? "127.0.0.1")
        _port = State(initialValue: editingItem?.port ?? (editingItem?.protocolType.defaultPort ?? 22))
        _username = State(initialValue: editingItem?.username ?? (NSUserName()))
        _authMethod = State(initialValue: editingItem?.authMethod ?? "password")
        _privateKeyPath = State(initialValue: editingItem?.privateKeyPath ?? "")
        _terminalType = State(initialValue: editingItem?.terminalType ?? "xterm-256color")
        _keepAliveInterval = State(initialValue: editingItem?.keepAliveInterval ?? 30)
        _encoding = State(initialValue: editingItem?.encoding ?? "UTF-8")
        _initialDirectory = State(initialValue: editingItem?.initialDirectory ?? "")
        _startupCommand = State(initialValue: editingItem?.startupCommand ?? "")
        _proxyJump = State(initialValue: editingItem?.proxyJump ?? "")
        _portForwardingRules = State(initialValue: editingItem?.portForwardingRules ?? "")
        _serialDevicePath = State(initialValue: editingItem?.serialDevicePath ?? "/dev/cu.usbserial")
        _baudRate = State(initialValue: editingItem?.baudRate ?? 115200)
        _dataBits = State(initialValue: editingItem?.dataBits ?? 8)
        _stopBits = State(initialValue: editingItem?.stopBits ?? 1)
        _parity = State(initialValue: editingItem?.parity ?? "none")
        _flowControl = State(initialValue: editingItem?.flowControl ?? "none")
        _sftpLocalPath = State(initialValue: editingItem?.sftpLocalPath ?? "")
        _sftpRemotePath = State(initialValue: editingItem?.sftpRemotePath ?? "")
        _sftpShowHidden = State(initialValue: editingItem?.sftpShowHidden ?? true)
        _vncColorDepth = State(initialValue: editingItem?.vncColorDepth ?? 24)
        _vncViewOnly = State(initialValue: editingItem?.vncViewOnly ?? false)
        _bleDeviceName = State(initialValue: editingItem?.bleDeviceName ?? "ESP32-Console")
        _bleServiceUUID = State(initialValue: editingItem?.bleServiceUUID ?? "0000FFE0-0000-1000-8000-00805F9B34FB")
        _bleCharacteristicUUID = State(initialValue: editingItem?.bleCharacteristicUUID ?? "0000FFE1-0000-1000-8000-00805F9B34FB")
        _bleMtu = State(initialValue: editingItem?.bleMtu ?? 247)
        _colorHex = State(initialValue: editingItem?.colorHex ?? "#3B82F6")
        
        var initialParentId: UUID? = parentGroupId
        if let editId = editingItem?.id, initialParentId == nil {
            for group in sessionStore.rootItems where group.isGroup {
                if group.children?.contains(where: { $0.id == editId }) == true {
                    initialParentId = group.id
                    break
                }
            }
        }
        _selectedGroupId = State(initialValue: initialParentId)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editingItem == nil ? (isGroup ? "新建分组" : "新建会话") : (isGroup ? "编辑分组" : "编辑会话"))
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main Body
            if isGroup {
                VStack(alignment: .leading, spacing: 16) {
                    FormFieldRow(label: "分组名称") {
                        TextField("输入分组名称 (如：生产集群、网络交换机)", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    FormFieldRow(label: "分组颜色") {
                        HStack(spacing: 10) {
                            ForEach(presetColors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(NSColor(hex: hex)))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: colorHex == hex ? 2.5 : 0)
                                    )
                                    .onTapGesture { colorHex = hex }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            } else {
                HStack(spacing: 0) {
                    // Left Protocol Selector Sidebar
                    VStack(alignment: .leading, spacing: 4) {
                        Text("协议类型")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 3) {
                                ForEach(SessionProtocol.allCases) { proto in
                                    ProtocolSidebarRow(
                                        proto: proto,
                                        isSelected: protocolType == proto,
                                        onSelect: {
                                            protocolType = proto
                                            port = proto.defaultPort
                                            if name.isEmpty || name.contains("会话") {
                                                name = "\(proto.rawValue) 会话"
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        Spacer()
                    }
                    .frame(width: 150)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    
                    Divider()
                    
                    // Right Content Area (Segmented Tabs + Form)
                    VStack(spacing: 0) {
                        Picker("", selection: $activeTab) {
                            ForEach(availableTabs, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                        
                        Divider()
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 13) {
                                switch activeTab {
                                case .general:
                                    generalSettingsView
                                case .advanced:
                                    advancedSettingsView
                                case .network:
                                    networkTunnelSettingsView
                                }
                            }
                            .padding(20)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            
            Divider()
            
            // Bottom Action Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("凭据密码受本地硬件级 AES-256 加密保护")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                
                Button("保存") {
                    saveAction()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 710, height: 530)
        .onAppear {
            scanSerialPorts()
            if let item = editingItem {
                if let storedPass = KeychainHelper.shared.read(key: item.credentialKey) {
                    self.password = storedPass
                }
                if let passKey = item.passphraseKey, let storedPassphrase = KeychainHelper.shared.read(key: passKey) {
                    self.passphrase = storedPassphrase
                }
            }
        }
    }
    
    private var availableTabs: [ConfigTab] {
        if protocolType == .ssh {
            return [.general, .advanced, .network]
        } else {
            return [.general, .advanced]
        }
    }
    
    // MARK: - Tab Views
    
    @ViewBuilder
    private var generalSettingsView: some View {
        FormFieldRow(label: "会话名称") {
            TextField("会话备注名称 (如: 生产网关、核心交换机)", text: $name)
                .textFieldStyle(.roundedBorder)
        }
        
        FormFieldRow(label: "所属分组") {
            Picker("", selection: $selectedGroupId) {
                Text("根目录 (无分组)").tag(UUID?.none)
                ForEach(availableGroups, id: \.id) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            .labelsHidden()
        }
        
        if protocolType == .local {
            FormFieldRow(label: "工作目录") {
                TextField("登录后默认进入目录 (例如 ~ 或 ~/Documents)", text: $initialDirectory)
                    .textFieldStyle(.roundedBorder)
            }
            
            FormFieldRow(label: "登录 Shell") {
                Picker("", selection: $startupCommand) {
                    Text("默认 Zsh (/bin/zsh)").tag("")
                    Text("Bash (/bin/bash)").tag("/bin/bash")
                    Text("Sh (/bin/sh)").tag("/bin/sh")
                }
                .labelsHidden()
            }
        } else if protocolType == .ble {
            FormFieldRow(label: "设备名称") {
                TextField("蓝牙设备名称或 UUID 过滤 (如 ESP32-BLE)", text: $bleDeviceName)
                    .textFieldStyle(.roundedBorder)
            }
            
            FormFieldRow(label: "服务 UUID") {
                TextField("0000FFE0-0000-1000-8000-00805F9B34FB", text: $bleServiceUUID)
                    .textFieldStyle(.roundedBorder)
            }
            
            FormFieldRow(label: "特征 UUID") {
                TextField("0000FFE1-0000-1000-8000-00805F9B34FB", text: $bleCharacteristicUUID)
                    .textFieldStyle(.roundedBorder)
            }
            
            FormFieldRow(label: "MTU 大小") {
                Picker("", selection: $bleMtu) {
                    Text("247 字节 (标准 BLE)").tag(247)
                    Text("512 字节 (高速)").tag(512)
                    Text("128 字节 (传统兼容)").tag(128)
                }
                .labelsHidden()
            }
        } else if protocolType == .serial {
            FormFieldRow(label: "串口设备") {
                HStack(spacing: 8) {
                    Picker("", selection: $serialDevicePath) {
                        ForEach(detectedSerialPorts, id: \.self) { dev in
                            Text(dev).tag(dev)
                        }
                    }
                    .labelsHidden()
                    
                    Button(action: { scanSerialPorts() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("重新扫描系统中可用的串口设备")
                }
            }
            
            FormFieldRow(label: "波特率") {
                Picker("", selection: $baudRate) {
                    Text("9600").tag(9600)
                    Text("19200").tag(19200)
                    Text("38400").tag(38400)
                    Text("57600").tag(57600)
                    Text("115200 (常用)").tag(115200)
                    Text("230400").tag(230400)
                    Text("460800").tag(460800)
                    Text("921600").tag(921600)
                }
                .labelsHidden()
            }
        } else {
            FormFieldRow(label: "主机 (Host)") {
                TextField("IP 地址或域名 (如: 192.168.1.100)", text: $host)
                    .textFieldStyle(.roundedBorder)
            }
            
            FormFieldRow(label: "端口 (Port)") {
                HStack(spacing: 8) {
                    TextField("端口", value: $port, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    
                    Text("默认: \(protocolType.defaultPort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            if protocolType != .vnc {
                FormFieldRow(label: "用户名") {
                    TextField("登录用户名 (如: root, admin)", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                
                FormFieldRow(label: "认证方式") {
                    Picker("", selection: $authMethod) {
                        Text("密码认证").tag("password")
                        Text("私钥文件").tag("key")
                        Text("系统 SSH-Agent").tag("agent")
                        Text("免密 / 交互式").tag("none")
                    }
                    .labelsHidden()
                }
                
                if authMethod == "password" {
                    FormFieldRow(label: "密码") {
                        HStack(spacing: 6) {
                            if showPasswordPlain {
                                TextField("输入远程连接密码", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("输入远程连接密码", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button(action: togglePasswordVisibility) {
                                Image(systemName: showPasswordPlain ? "eye.slash" : "eye")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("查看明文密码 (需 Touch ID 验证)")
                        }
                    }
                } else if authMethod == "key" {
                    FormFieldRow(label: "私钥路径") {
                        HStack(spacing: 6) {
                            TextField("~/.ssh/id_rsa", text: $privateKeyPath)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("浏览...") { choosePrivateKeyFile() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    
                    FormFieldRow(label: "私钥密码") {
                        HStack(spacing: 6) {
                            if showPassphrasePlain {
                                TextField("若私钥无密码可留空", text: $passphrase)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("若私钥无密码可留空", text: $passphrase)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button(action: togglePassphraseVisibility) {
                                Image(systemName: showPassphrasePlain ? "eye.slash" : "eye")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("查看明文密码 (需 Touch ID 验证)")
                        }
                    }
                }
            } else {
                FormFieldRow(label: "VNC 密码") {
                    SecureField("输入远程桌面连接密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        
        FormFieldRow(label: "标签颜色") {
            HStack(spacing: 10) {
                ForEach(presetColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(NSColor(hex: hex)))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: colorHex == hex ? 2.5 : 0)
                        )
                        .shadow(color: colorHex == hex ? Color.accentColor.opacity(0.6) : Color.clear, radius: 4)
                        .onTapGesture { colorHex = hex }
                }
                Spacer()
            }
            .padding(.top, 2)
        }
    }
    
    @ViewBuilder
    private var advancedSettingsView: some View {
        if protocolType == .serial {
            FormFieldRow(label: "数据位") {
                Picker("", selection: $dataBits) {
                    Text("8 位 (标准)").tag(8)
                    Text("7 位").tag(7)
                    Text("6 位").tag(6)
                    Text("5 位").tag(5)
                }
                .labelsHidden()
            }
            
            FormFieldRow(label: "停止位") {
                Picker("", selection: $stopBits) {
                    Text("1 位 (标准)").tag(1)
                    Text("2 位").tag(2)
                }
                .labelsHidden()
            }
            
            FormFieldRow(label: "奇偶校验") {
                Picker("", selection: $parity) {
                    Text("无校验 (None)").tag("none")
                    Text("偶校验 (Even)").tag("even")
                    Text("奇校验 (Odd)").tag("odd")
                    Text("Mark 校验").tag("mark")
                    Text("Space 校验").tag("space")
                }
                .labelsHidden()
            }
            
            FormFieldRow(label: "流控制") {
                Picker("", selection: $flowControl) {
                    Text("无 (None)").tag("none")
                    Text("硬件流控 (RTS/CTS)").tag("rtscts")
                    Text("软件流控 (XON/XOFF)").tag("xonxoff")
                }
                .labelsHidden()
            }
        } else if protocolType == .vnc {
            FormFieldRow(label: "色彩深度") {
                Picker("", selection: $vncColorDepth) {
                    Text("24 位真彩色 (高清流畅)").tag(24)
                    Text("16 位增强色 (节省带宽)").tag(16)
                    Text("8 位低彩度 (超低延迟)").tag(8)
                }
                .labelsHidden()
            }
            
            FormFieldRow(label: "查看模式") {
                Toggle("仅查看模式 (禁用鼠标键盘远程控制)", isOn: $vncViewOnly)
                    .font(.system(size: 12))
            }
        } else {
            FormFieldRow(label: "终端仿真") {
                Picker("", selection: $terminalType) {
                    Text("xterm-256color (推荐)").tag("xterm-256color")
                    Text("xterm").tag("xterm")
                    Text("vt100 (兼容设备)").tag("vt100")
                    Text("linux").tag("linux")
                    Text("screen-256color").tag("screen-256color")
                }
                .labelsHidden()
            }
            
            FormFieldRow(label: "字符编码") {
                Picker("", selection: $encoding) {
                    Text("UTF-8 (国际通用)").tag("UTF-8")
                    Text("GBK / GB2312 (中文兼容)").tag("GBK")
                    Text("GB18030 (大字符集)").tag("GB18030")
                    Text("ISO-8859-1 (西欧)").tag("ISO-8859-1")
                }
                .labelsHidden()
            }
            
            FormFieldRow(label: "心跳保活") {
                HStack(spacing: 8) {
                    TextField("30", value: $keepAliveInterval, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("秒 (ServerAliveInterval，防连接掉线超时)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            FormFieldRow(label: "初始目录") {
                TextField("登录后默认进入目录 (例如 /var/log, 留空为默认家目录)", text: $initialDirectory)
                    .textFieldStyle(.roundedBorder)
            }
            
            FormFieldRow(label: "启动脚本") {
                TextField("连接建立后自动执行命令 (例如 htop 或 tmux a)", text: $startupCommand)
                    .textFieldStyle(.roundedBorder)
            }
            
            if protocolType == .ftp {
                FormFieldRow(label: "隐藏文件") {
                    Toggle("自动显示以点号开头的隐藏文件", isOn: $sftpShowHidden)
                        .font(.system(size: 12))
                }
            }
        }
    }
    
    @ViewBuilder
    private var networkTunnelSettingsView: some View {
        FormFieldRow(label: "跳板机穿透") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("ProxyJump 地址 (例如: jumpuser@10.0.0.1:22)", text: $proxyJump)
                    .textFieldStyle(.roundedBorder)
                Text("通过跳板机/堡垒机中继访问目标私网服务器")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        
        FormFieldRow(label: "端口转发") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("转发规则 (例如: -L 8080:127.0.0.1:80 -D 1080)", text: $portForwardingRules)
                    .textFieldStyle(.roundedBorder)
                Text("支持本地转发 (-L)、远程转发 (-R) 及动态 Socks5 代理 (-D)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Actions
    
    private func scanSerialPorts() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: "/dev") {
            let cuFiles = files.filter { $0.hasPrefix("cu.") }.map { "/dev/\($0)" }
            if !cuFiles.isEmpty {
                self.detectedSerialPorts = cuFiles
                if !cuFiles.contains(serialDevicePath) {
                    self.serialDevicePath = cuFiles.first ?? "/dev/cu.usbserial"
                }
                return
            }
        }
        self.detectedSerialPorts = ["/dev/cu.usbserial", "/dev/cu.wchusbserial", "/dev/cu.Bluetooth-Incoming-Port"]
    }
    
    private func togglePasswordVisibility() {
        if showPasswordPlain {
            showPasswordPlain = false
        } else {
            if !password.isEmpty {
                Task {
                    let success = await BiometricGuard.shared.authenticate(reason: "查看已保存的服务器连接密码")
                    if success {
                        HapticFeedbackHelper.shared.performGeneric()
                        showPasswordPlain = true
                    } else {
                        HapticFeedbackHelper.shared.performLevelChange()
                    }
                }
            } else {
                showPasswordPlain = true
            }
        }
    }
    
    private func togglePassphraseVisibility() {
        if showPassphrasePlain {
            showPassphrasePlain = false
        } else {
            if !passphrase.isEmpty {
                Task {
                    let success = await BiometricGuard.shared.authenticate(reason: "查看已保存的私钥口令密码")
                    if success {
                        HapticFeedbackHelper.shared.performGeneric()
                        showPassphrasePlain = true
                    } else {
                        HapticFeedbackHelper.shared.performLevelChange()
                    }
                }
            } else {
                showPassphrasePlain = true
            }
        }
    }
    
    private func choosePrivateKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            self.privateKeyPath = url.path
        }
    }
    
    private func saveAction() {
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (isGroup ? "新建分组" : "\(protocolType.rawValue) 会话") : name
        let credKey = editingItem?.credentialKey ?? UUID().uuidString
        if !password.isEmpty {
            KeychainHelper.shared.save(key: credKey, secret: password)
        }
        
        var passKey = editingItem?.passphraseKey
        if !passphrase.isEmpty {
            if passKey == nil { passKey = UUID().uuidString }
            KeychainHelper.shared.save(key: passKey!, secret: passphrase)
        }
        
        let newItem = SessionItem(
            id: editingItem?.id ?? UUID(),
            name: finalName,
            isGroup: isGroup,
            iconName: isGroup ? "folder.fill" : protocolType.iconName,
            colorHex: colorHex,
            protocolType: protocolType,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: authMethod,
            privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath,
            credentialKey: credKey,
            passphraseKey: passKey,
            terminalType: terminalType,
            keepAliveInterval: keepAliveInterval,
            encoding: encoding,
            initialDirectory: initialDirectory.isEmpty ? nil : initialDirectory,
            startupCommand: startupCommand.isEmpty ? nil : startupCommand,
            proxyJump: proxyJump.isEmpty ? nil : proxyJump,
            portForwardingRules: portForwardingRules.isEmpty ? nil : portForwardingRules,
            serialDevicePath: serialDevicePath,
            baudRate: baudRate,
            dataBits: dataBits,
            stopBits: stopBits,
            parity: parity,
            flowControl: flowControl,
            sftpLocalPath: sftpLocalPath.isEmpty ? nil : sftpLocalPath,
            sftpRemotePath: sftpRemotePath.isEmpty ? nil : sftpRemotePath,
            sftpShowHidden: sftpShowHidden,
            vncColorDepth: vncColorDepth,
            vncViewOnly: vncViewOnly,
            bleDeviceName: bleDeviceName.isEmpty ? nil : bleDeviceName,
            bleServiceUUID: bleServiceUUID.isEmpty ? nil : bleServiceUUID,
            bleCharacteristicUUID: bleCharacteristicUUID.isEmpty ? nil : bleCharacteristicUUID,
            bleMtu: bleMtu,
            children: isGroup ? (editingItem?.children ?? []) : nil
        )
        
        if isGroup {
            if editingItem != nil {
                sessionStore.updateSession(newItem)
            } else {
                sessionStore.addSession(newItem)
            }
        } else {
            sessionStore.saveOrMoveSession(newItem, newParentId: selectedGroupId)
        }
    }
}

// MARK: - Protocol Sidebar Row Component (Full Area Clickable)
private struct ProtocolSidebarRow: View {
    let proto: SessionProtocol
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: proto.iconName)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : protocolColor(proto))
                    .frame(width: 18)
                
                Text(proto.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.12) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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

// MARK: - Form Field Alignment Helper
private struct FormFieldRow<Content: View>: View {
    let label: String
    let content: Content
    
    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
