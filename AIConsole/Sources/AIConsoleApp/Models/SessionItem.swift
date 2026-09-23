import Foundation

public struct SessionItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var isGroup: Bool
    public var iconName: String
    public var colorHex: String?
    
    // Connection specific details
    public var protocolType: SessionProtocol
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: String // "password", "key", "agent", "none"
    public var privateKeyPath: String?
    public var credentialKey: String // Key reference for Keychain
    public var passphraseKey: String? // Passphrase for private key
    
    // SSH & Terminal Advanced Options
    public var terminalType: String // "xterm-256color", "xterm", "vt100", "linux"
    public var keepAliveInterval: Int // Seconds (e.g. 30)
    public var encoding: String // "UTF-8", "GBK", "GB18030", "ISO-8859-1"
    public var initialDirectory: String?
    public var startupCommand: String?
    public var proxyJump: String? // Jump host (e.g. bastion@1.2.3.4:22)
    public var portForwardingRules: String? // Local/Remote/Dynamic tunnels
    
    // Serial specific
    public var serialDevicePath: String?
    public var baudRate: Int
    public var dataBits: Int
    public var stopBits: Int
    public var parity: String // "none", "even", "odd", "mark", "space"
    public var flowControl: String // "none", "rtscts", "xonxoff"
    
    // SFTP specific
    public var sftpLocalPath: String?
    public var sftpRemotePath: String?
    public var sftpShowHidden: Bool
    
    // VNC specific
    public var vncColorDepth: Int // 8, 16, 24
    public var vncViewOnly: Bool
    
    // BLE specific
    public var bleDeviceName: String?
    public var bleServiceUUID: String?
    public var bleCharacteristicUUID: String?
    public var bleMtu: Int
    
    // Hierarchy
    public var children: [SessionItem]?
    
    public init(
        id: UUID = UUID(),
        name: String,
        isGroup: Bool = false,
        iconName: String = "terminal.fill",
        colorHex: String? = nil,
        protocolType: SessionProtocol = .ssh,
        host: String = "127.0.0.1",
        port: Int = 22,
        username: String = "root",
        authMethod: String = "password",
        privateKeyPath: String? = nil,
        credentialKey: String = UUID().uuidString,
        passphraseKey: String? = nil,
        terminalType: String = "xterm-256color",
        keepAliveInterval: Int = 30,
        encoding: String = "UTF-8",
        initialDirectory: String? = nil,
        startupCommand: String? = nil,
        proxyJump: String? = nil,
        portForwardingRules: String? = nil,
        serialDevicePath: String? = nil,
        baudRate: Int = 115200,
        dataBits: Int = 8,
        stopBits: Int = 1,
        parity: String = "none",
        flowControl: String = "none",
        sftpLocalPath: String? = nil,
        sftpRemotePath: String? = nil,
        sftpShowHidden: Bool = true,
        vncColorDepth: Int = 24,
        vncViewOnly: Bool = false,
        bleDeviceName: String? = nil,
        bleServiceUUID: String? = nil,
        bleCharacteristicUUID: String? = nil,
        bleMtu: Int = 247,
        children: [SessionItem]? = nil
    ) {
        self.id = id
        self.name = name
        self.isGroup = isGroup
        self.iconName = iconName
        self.colorHex = colorHex
        self.protocolType = protocolType
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.credentialKey = credentialKey
        self.passphraseKey = passphraseKey
        self.terminalType = terminalType
        self.keepAliveInterval = keepAliveInterval
        self.encoding = encoding
        self.initialDirectory = initialDirectory
        self.startupCommand = startupCommand
        self.proxyJump = proxyJump
        self.portForwardingRules = portForwardingRules
        self.serialDevicePath = serialDevicePath
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.stopBits = stopBits
        self.parity = parity
        self.flowControl = flowControl
        self.sftpLocalPath = sftpLocalPath
        self.sftpRemotePath = sftpRemotePath
        self.sftpShowHidden = sftpShowHidden
        self.vncColorDepth = vncColorDepth
        self.vncViewOnly = vncViewOnly
        self.bleDeviceName = bleDeviceName
        self.bleServiceUUID = bleServiceUUID
        self.bleCharacteristicUUID = bleCharacteristicUUID
        self.bleMtu = bleMtu
        self.children = children
    }
    
    // Custom Decodable initializer for seamless backwards compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "会话"
        self.isGroup = try container.decodeIfPresent(Bool.self, forKey: .isGroup) ?? false
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "terminal.fill"
        self.colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        self.protocolType = try container.decodeIfPresent(SessionProtocol.self, forKey: .protocolType) ?? .ssh
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? "root"
        self.authMethod = try container.decodeIfPresent(String.self, forKey: .authMethod) ?? "password"
        self.privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath)
        self.credentialKey = try container.decodeIfPresent(String.self, forKey: .credentialKey) ?? UUID().uuidString
        self.passphraseKey = try container.decodeIfPresent(String.self, forKey: .passphraseKey)
        self.terminalType = try container.decodeIfPresent(String.self, forKey: .terminalType) ?? "xterm-256color"
        self.keepAliveInterval = try container.decodeIfPresent(Int.self, forKey: .keepAliveInterval) ?? 30
        self.encoding = try container.decodeIfPresent(String.self, forKey: .encoding) ?? "UTF-8"
        self.initialDirectory = try container.decodeIfPresent(String.self, forKey: .initialDirectory)
        self.startupCommand = try container.decodeIfPresent(String.self, forKey: .startupCommand)
        self.proxyJump = try container.decodeIfPresent(String.self, forKey: .proxyJump)
        self.portForwardingRules = try container.decodeIfPresent(String.self, forKey: .portForwardingRules)
        self.serialDevicePath = try container.decodeIfPresent(String.self, forKey: .serialDevicePath)
        self.baudRate = try container.decodeIfPresent(Int.self, forKey: .baudRate) ?? 115200
        self.dataBits = try container.decodeIfPresent(Int.self, forKey: .dataBits) ?? 8
        self.stopBits = try container.decodeIfPresent(Int.self, forKey: .stopBits) ?? 1
        self.parity = try container.decodeIfPresent(String.self, forKey: .parity) ?? "none"
        self.flowControl = try container.decodeIfPresent(String.self, forKey: .flowControl) ?? "none"
        self.sftpLocalPath = try container.decodeIfPresent(String.self, forKey: .sftpLocalPath)
        self.sftpRemotePath = try container.decodeIfPresent(String.self, forKey: .sftpRemotePath)
        self.sftpShowHidden = try container.decodeIfPresent(Bool.self, forKey: .sftpShowHidden) ?? true
        self.vncColorDepth = try container.decodeIfPresent(Int.self, forKey: .vncColorDepth) ?? 24
        self.vncViewOnly = try container.decodeIfPresent(Bool.self, forKey: .vncViewOnly) ?? false
        self.bleDeviceName = try container.decodeIfPresent(String.self, forKey: .bleDeviceName)
        self.bleServiceUUID = try container.decodeIfPresent(String.self, forKey: .bleServiceUUID)
        self.bleCharacteristicUUID = try container.decodeIfPresent(String.self, forKey: .bleCharacteristicUUID)
        self.bleMtu = try container.decodeIfPresent(Int.self, forKey: .bleMtu) ?? 247
        self.children = try container.decodeIfPresent([SessionItem].self, forKey: .children)
    }
}
