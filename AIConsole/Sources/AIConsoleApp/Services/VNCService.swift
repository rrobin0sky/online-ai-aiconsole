import Foundation
import AppKit
import Network

@MainActor
public final class VNCService: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var statusMessage: String = "未连接"
    @Published public var serverVersion: String?
    @Published public var remoteScreenImage: NSImage?
    @Published public var isProbing: Bool = false
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aiconsole.vnc.probe", qos: .userInitiated)
    
    public init() {}
    
    public func probeAndConnect(host: String, port: Int, password: String?) {
        disconnect()
        isProbing = true
        statusMessage = "正在探测 VNC/RFB 服务 (\(host):\(port))..."
        
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            statusMessage = "无效端口号: \(port)"
            isProbing = false
            return
        }
        
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.statusMessage = "TCP 端口已就绪，正在进行 RFB 协议握手..."
                    self.receiveRFBVersion(host: host, port: port)
                case .failed(let err):
                    self.statusMessage = "连接失败: \(err.localizedDescription)"
                    self.isConnected = false
                    self.isProbing = false
                case .cancelled:
                    self.statusMessage = "连接已取消"
                    self.isConnected = false
                    self.isProbing = false
                default:
                    break
                }
            }
        }
        
        conn.start(queue: queue)
    }
    
    private func receiveRFBVersion(host: String, port: Int) {
        connection?.receive(minimumIncompleteLength: 12, maximumLength: 12) { [weak self] content, _, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isProbing = false
                if let data = content, let versionStr = String(data: data, encoding: .utf8), versionStr.hasPrefix("RFB ") {
                    let cleanVersion = versionStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.serverVersion = cleanVersion
                    self.isConnected = true
                    self.statusMessage = "RFB 握手成功: \(cleanVersion) (服务在线)"
                    self.renderDesktopPlaceholder(host: host, port: port, version: cleanVersion)
                } else if error != nil {
                    self.statusMessage = "握手超时或非标准 VNC 服务"
                } else {
                    self.isConnected = true
                    self.statusMessage = "VNC 端口开放，已就绪"
                    self.renderDesktopPlaceholder(host: host, port: port, version: "RFB 3.8")
                }
            }
        }
    }
    
    public func launchNativeScreenSharing(host: String, port: Int, username: String? = nil, password: String? = nil) {
        var urlString = "vnc://"
        if let user = username, !user.isEmpty {
            if let pass = password, !pass.isEmpty {
                urlString += "\(user):\(pass)@"
            } else {
                urlString += "\(user)@"
            }
        }
        urlString += "\(host):\(port)"
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func renderDesktopPlaceholder(host: String, port: Int, version: String) {
        let size = NSSize(width: 1024, height: 768)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(hex: "#16161E").setFill()
        NSRect(origin: .zero, size: size).fill()
        
        let attrsTitle: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(hex: "#00E5FF"),
            .font: NSFont.systemFont(ofSize: 22, weight: .bold)
        ]
        let title = "🖥️ VNC 远程桌面服务在线"
        title.draw(at: NSPoint(x: 360, y: 440), withAttributes: attrsTitle)
        
        let attrsSub: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(hex: "#A9B1D6"),
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        ]
        let info = "目标地址: \(host):\(port)\n协议版本: \(version)\n点击下方按钮在 macOS 原生高清硬件加速窗口中操作"
        info.draw(at: NSPoint(x: 310, y: 360), withAttributes: attrsSub)
        
        img.unlockFocus()
        self.remoteScreenImage = img
    }
    
    public func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        isProbing = false
        statusMessage = "未连接"
        remoteScreenImage = nil
    }
}
