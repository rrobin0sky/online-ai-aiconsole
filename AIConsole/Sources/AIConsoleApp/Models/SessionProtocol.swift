import Foundation

public enum SessionProtocol: String, Codable, CaseIterable, Identifiable {
    case ssh = "SSH"
    case serial = "Serial"
    case ble = "蓝牙 Console"
    case telnet = "Telnet"
    case sftp = "SFTP"
    case scp = "SCP"
    case ftp = "FTP"
    case vnc = "VNC"
    case local = "本地终端"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .ssh: return "terminal.fill"
        case .sftp: return "folder.fill.badge.gearshape"
        case .scp: return "arrow.triangle.2.circlepath.doc.on.clipboard"
        case .telnet: return "network"
        case .serial: return "cable.connector"
        case .ble: return "dot.radiowaves.left.and.right"
        case .local: return "apple.terminal.fill"
        case .vnc: return "display.2"
        case .ftp: return "folder.badge.gearshape"
        }
    }
    
    public var defaultPort: Int {
        switch self {
        case .ssh, .sftp, .scp: return 22
        case .telnet: return 23
        case .serial: return 115200 // baud rate for serial
        case .vnc: return 5900
        case .ftp: return 21
        case .ble, .local: return 0
        }
    }
    
    public var isTerminalSupported: Bool {
        switch self {
        case .ssh, .telnet, .serial, .ble, .local: return true
        case .sftp, .scp, .ftp, .vnc: return false
        }
    }
}
