import SwiftUI

public struct VNCView: View {
    let session: SessionItem
    @StateObject private var vncService = VNCService()
    
    public init(session: SessionItem) {
        self.session = session
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Status & Quick Action Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vncService.isConnected ? Color.green : (vncService.isProbing ? Color.yellow : Color.red))
                        .frame(width: 8, height: 8)
                    Text(vncService.statusMessage)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: openInNativeScreenSharing) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("在 macOS 原生高清窗口中打开")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("使用 macOS 系统级硬件加速 Screen Sharing 客户端连接")
                
                Button(action: copyVncURL) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("复制 vnc:// 链接")
                
                Button(action: probe) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("重新检测 VNC 服务")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Canvas View
            GeometryReader { geo in
                ZStack {
                    Color(NSColor(hex: "#16161E"))
                    
                    if let img = vncService.remoteScreenImage {
                        VStack(spacing: 20) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: min(geo.size.width - 40, 900), maxHeight: min(geo.size.height - 120, 600))
                                .cornerRadius(8)
                                .shadow(radius: 10)
                            
                            Button(action: openInNativeScreenSharing) {
                                HStack(spacing: 8) {
                                    Image(systemName: "display")
                                    Text("立即进入远程桌面操作控制台")
                                }
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        VStack(spacing: 12) {
                            if vncService.isProbing {
                                ProgressView()
                                Text("正在探测 \(session.host):\(session.port) RFB 协议...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "display.trianglebadge.exclamationmark")
                                    .font(.system(size: 40))
                                    .foregroundColor(.yellow)
                                Text("未检测到活跃的 VNC/RFB 服务")
                                    .font(.headline)
                                Button("尝试原生直连", action: openInNativeScreenSharing)
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            probe()
        }
    }
    
    private func probe() {
        let password = KeychainHelper.shared.read(key: session.credentialKey)
        vncService.probeAndConnect(host: session.host, port: session.port, password: password)
    }
    
    private func openInNativeScreenSharing() {
        let password = KeychainHelper.shared.read(key: session.credentialKey)
        vncService.launchNativeScreenSharing(
            host: session.host,
            port: session.port,
            username: session.username.isEmpty ? nil : session.username,
            password: password
        )
    }
    
    private func copyVncURL() {
        let url = "vnc://\(session.host):\(session.port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
}
