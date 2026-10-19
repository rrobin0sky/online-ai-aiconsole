import Foundation

/// Utility to clean terminal escape codes, ANSI colors, cursor movements,
/// bracketed paste markers, and backspace artifacts from terminal output streams,
/// producing clean, audit-grade human-readable plain text.
public enum TerminalTextSanitizer {
    
    // Pre-compiled regular expressions for high performance stream cleaning
    private static let oscRegex = try? NSRegularExpression(
        pattern: #"\\x1b\][^\u0007\\x1b]*(\u0007|\\x1b\\)"#,
        options: []
    )
    
    private static let csiRegex = try? NSRegularExpression(
        pattern: #"\\x1b\[[0-9;?><=!]*[a-zA-Z~]"#,
        options: []
    )
    
    private static let esc2Regex = try? NSRegularExpression(
        pattern: #"\\x1b[@-Z\\-_]"#,
        options: []
    )
    
    private static let controlCharsRegex = try? NSRegularExpression(
        pattern: #"[\u0000-\u0007\u000b\u000c\u000e-\u001f]"#,
        options: []
    )
    
    private static let zshPromptArtifactRegex = try? NSRegularExpression(
        pattern: #"(?m)^%\s{10,}\n?"#,
        options: []
    )
    
    /// Sanitizes raw terminal byte stream string into clean, human-readable text.
    public static func clean(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        
        var text = raw
        
        // 1. Strip OSC sequences (e.g. window title \x1b]0;...\x07, shell integration \x1b]133;...\x07)
        if let regex = oscRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // 2. Strip CSI sequences (e.g. \x1b[?2004h bracketed paste, \x1b[0m colors, \x1b[K erases, cursor moves)
        if let regex = csiRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // 3. Strip 2-character escape sequences (e.g. \x1b=, \x1b>, \x1b(B)
        if let regex = esc2Regex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // 4. Normalize newlines
        text = text.replacingOccurrences(of: "\r\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "")
        
        // 5. Resolve interactive backspaces (\u{08} and \u{7f})
        if text.contains("\u{08}") || text.contains("\u{7f}") {
            var resolved: [Character] = []
            for ch in text {
                if ch == "\u{08}" || ch == "\u{7f}" {
                    if !resolved.isEmpty && resolved.last != "\n" {
                        resolved.removeLast()
                    }
                } else {
                    resolved.append(ch)
                }
            }
            text = String(resolved)
        }
        
        // 6. Strip stray non-printable control characters (keeping \t and \n)
        if let regex = controlCharsRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        // 7. Strip zsh % blank line padding artifact
        if let regex = zshPromptArtifactRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        return text
    }
}
