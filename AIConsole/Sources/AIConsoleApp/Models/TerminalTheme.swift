import AppKit
import Foundation

public struct TerminalTheme: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let backgroundHex: String
    public let foregroundHex: String
    public let cursorHex: String
    public let selectionHex: String
    
    // ANSI 16 colors
    public let ansiHexColors: [String]
    
    public init(id: String, name: String, backgroundHex: String, foregroundHex: String, cursorHex: String, selectionHex: String, ansiHexColors: [String]) {
        self.id = id
        self.name = name
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.cursorHex = cursorHex
        self.selectionHex = selectionHex
        self.ansiHexColors = ansiHexColors
    }
    
    public var backgroundColor: NSColor { NSColor(hex: backgroundHex) }
    public var foregroundColor: NSColor { NSColor(hex: foregroundHex) }
    public var cursorColor: NSColor { NSColor(hex: cursorHex) }
    
    // MARK: - 1. 🌌 Midnight Pro (Apple 官方深邃黑)
    public static let midnightPro = TerminalTheme(
        id: "midnight-pro",
        name: "🌌 Midnight Pro (Apple 深邃黑)",
        backgroundHex: "#0D1117",
        foregroundHex: "#E6EDF3",
        cursorHex: "#58A6FF",
        selectionHex: "#1F6FEB",
        ansiHexColors: [
            "#0D1117", "#FF7B72", "#3FB950", "#D29922", "#58A6FF", "#BC8CFF", "#39C5CF", "#D0D7DE",
            "#484F58", "#FFA198", "#56D364", "#E3B341", "#79C0FF", "#D2A8FF", "#56D4DD", "#FFFFFF"
        ]
    )
    
    // MARK: - 2. 🧛 Dracula Modern (吸血鬼极客紫)
    public static let dracula = TerminalTheme(
        id: "dracula",
        name: "🧛 Dracula Modern (极客紫)",
        backgroundHex: "#282A36",
        foregroundHex: "#F8F8F2",
        cursorHex: "#FF79C6",
        selectionHex: "#44475A",
        ansiHexColors: [
            "#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
            "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"
        ]
    )
    
    // MARK: - 3. 🐱 Catppuccin Mocha (柔和马卡龙暗色)
    public static let catppuccin = TerminalTheme(
        id: "catppuccin",
        name: "🐱 Catppuccin Mocha (柔和暗黑)",
        backgroundHex: "#1E1E2E",
        foregroundHex: "#CDD6F4",
        cursorHex: "#F5E0DC",
        selectionHex: "#45475A",
        ansiHexColors: [
            "#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#CBA6F7", "#94E2D5", "#BAC2DE",
            "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#CBA6F7", "#94E2D5", "#A6ADC8"
        ]
    )
    
    // MARK: - 4. 🌿 Solarized Dark (经典护眼深青)
    public static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "🌿 Solarized Dark (经典深青)",
        backgroundHex: "#002B36",
        foregroundHex: "#839496",
        cursorHex: "#268BD2",
        selectionHex: "#073642",
        ansiHexColors: [
            "#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
            "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"
        ]
    )
    
    // MARK: - 5. ⚡ Cyberpunk Neon (赛博朋克高对比霓虹)
    public static let cyberpunk = TerminalTheme(
        id: "cyberpunk",
        name: "⚡ Cyberpunk Neon (赛博霓虹)",
        backgroundHex: "#120E24",
        foregroundHex: "#00FFCC",
        cursorHex: "#FF007F",
        selectionHex: "#3D1B5B",
        ansiHexColors: [
            "#1A1438", "#FF0055", "#00FF99", "#FFE600", "#00D4FF", "#BD00FF", "#00FFCC", "#FFFFFF",
            "#4A3E7A", "#FF3377", "#33FFAD", "#FFEC33", "#33DDFF", "#CA33FF", "#33FFD6", "#FFFFFF"
        ]
    )
    
    // MARK: - 6. ☀️ Paper Light (苹果纯净明亮模式)
    public static let paperLight = TerminalTheme(
        id: "paper-light",
        name: "☀️ Paper Light (纯净高光)",
        backgroundHex: "#F8F9FA",
        foregroundHex: "#212529",
        cursorHex: "#0066CC",
        selectionHex: "#CCE5FF",
        ansiHexColors: [
            "#E9ECEF", "#D90429", "#2B9348", "#E85D04", "#0077B6", "#7209B7", "#0096C7", "#212529",
            "#ADB5BD", "#EF233C", "#55A630", "#F48C06", "#023E8A", "#560BAD", "#0077B6", "#000000"
        ]
    )
    
    // MARK: - 7. 🌐 NetOps Cyber Pro (网络工程师旗舰专属)
    public static let netOpsPro = TerminalTheme(
        id: "netops-pro",
        name: "🌐 NetOps Cyber Pro (旗舰网络色)",
        backgroundHex: "#16161E",
        foregroundHex: "#E2E8F0",
        cursorHex: "#00E5FF",
        selectionHex: "#33467C",
        ansiHexColors: [
            "#1A1B26", "#FF5555", "#50FA7B", "#FFB86C", "#00D2FF", "#BD93F9", "#8BE9FD", "#F8F8F2",
            "#444B6A", "#FF6E6E", "#69FF94", "#FFE066", "#40EAFF", "#D6ACFF", "#A4FFFF", "#FFFFFF"
        ]
    )
    
    public static let defaultTheme = netOpsPro
    public static let allThemes: [TerminalTheme] = [
        netOpsPro,
        midnightPro,
        dracula,
        catppuccin,
        solarizedDark,
        cyberpunk,
        paperLight
    ]
}

extension NSColor {
    convenience init(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        
        let r, g, b, a: CGFloat
        if cleanHex.count == 6 {
            r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgbValue & 0x0000FF) / 255.0
            a = 1.0
        } else if cleanHex.count == 8 {
            r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgbValue & 0x000000FF) / 255.0
        } else {
            r = 0.5; g = 0.5; b = 0.5; a = 1.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
