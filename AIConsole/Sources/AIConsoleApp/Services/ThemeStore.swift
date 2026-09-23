import SwiftUI
import AppKit

@MainActor
public final class ThemeStore: ObservableObject {
    public static let shared = ThemeStore()
    
    @Published public var currentTheme: TerminalTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.id, forKey: "user_terminal_theme_id")
        }
    }
    
    @Published public var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "user_terminal_font_size")
        }
    }
    
    private init() {
        let savedThemeId = UserDefaults.standard.string(forKey: "user_terminal_theme_id") ?? TerminalTheme.defaultTheme.id
        self.currentTheme = TerminalTheme.allThemes.first(where: { $0.id == savedThemeId }) ?? TerminalTheme.defaultTheme
        
        let savedFontSize = UserDefaults.standard.double(forKey: "user_terminal_font_size")
        self.fontSize = savedFontSize > 8 ? CGFloat(savedFontSize) : 13.0
    }
    
    public func setTheme(_ theme: TerminalTheme) {
        self.currentTheme = theme
        HapticFeedbackHelper.shared.performAlignment()
    }
    
    public func zoomIn() {
        if fontSize < 24 {
            fontSize += 1
            HapticFeedbackHelper.shared.performGeneric()
        }
    }
    
    public func zoomOut() {
        if fontSize > 9 {
            fontSize -= 1
            HapticFeedbackHelper.shared.performGeneric()
        }
    }
    
    public func resetZoom() {
        fontSize = 13.0
        HapticFeedbackHelper.shared.performGeneric()
    }
}
