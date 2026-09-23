import Foundation

public final class SessionBannerService {
    public static let shared = SessionBannerService()
    
    public func generateStartupBanner(for session: SessionItem) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        
        let cyan = "\u{001B}[38;2;139;233;253;1m"
        let green = "\u{001B}[38;2;80;250;123;1m"
        let violet = "\u{001B}[38;2;189;147;249;1m"
        let white = "\u{001B}[38;2;248;248;242;1m"
        let reset = "\u{001B}[0m"
        
        let protocolInfo = session.protocolType.rawValue
        let target = session.protocolType == .serial ? (session.serialDevicePath ?? "Serial") : "\(session.username)@\(session.host):\(session.port)"
        
        var banner = "\r\n"
        banner += "\(cyan)┌─────────────────────────────────────────────────────────────┐\(reset)\r\n"
        banner += "\(cyan)│\(reset) \(white)🌐 AIConsole NetOps Session Initialized\(reset)                   \(cyan)│\(reset)\r\n"
        banner += "\(cyan)│\(reset) 📡 \(green)Protocol:\(reset) \(protocolInfo) | 🎯 \(green)Target:\(reset) \(target) \r\n"
        banner += "\(cyan)│\(reset) ⚡ \(violet)Status:\(reset) CONNECTED | 🔒 \(violet)Security:\(reset) Keychain Encrypted   \r\n"
        banner += "\(cyan)│\(reset) ⏰ \(white)Timestamp:\(reset) \(timestamp)                           \(cyan)│\(reset)\r\n"
        banner += "\(cyan)└─────────────────────────────────────────────────────────────┘\(reset)\r\n\r\n"
        
        return banner
    }
}
