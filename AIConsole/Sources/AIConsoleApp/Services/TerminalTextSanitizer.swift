import Foundation

/// Utility to clean terminal escape codes, ANSI colors, cursor movements,
/// bracketed paste markers, and backspace artifacts from terminal output streams,
/// producing clean, audit-grade human-readable plain text.
public enum TerminalTextSanitizer {
    
    // Pre-compiled regular expressions for high performance stream cleaning
    // Note: Inside Swift raw strings #"..."#, \x1b is a single backslash escape for ESC (0x1B).
    private static let oscRegex = try? NSRegularExpression(
        pattern: #"\x1b\][^\u0007\x1b]*(?:\u0007|\x1b\\)"#,
        options: []
    )
    
    private static let csiRegex = try? NSRegularExpression(
        pattern: #"\x1b\[[0-9;?><=! ]*[a-zA-Z~@`]"#,
        options: []
    )
    
    private static let esc2Regex = try? NSRegularExpression(
        pattern: #"\x1b[\(\)\*\+][0-9A-Za-z]|\x1b[@-Z\\-_]"#,
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

/// Stateful per-session stream processor for crash-proof line-oriented terminal recording.
/// Correctly handles:
/// - Single-byte / fragmented serial & SSH chunks (e.g. 9600 bps console output)
/// - Multi-byte UTF-8 characters split across chunk boundaries
/// - Cross-chunk ANSI CSI / OSC / ESC sequences
/// - Carriage-return (\r) progress bar overwrites (e.g. Scanning ... (0%) -> (100%))
/// - Interactive backspaces (\x08 / \x7f) and CSI Erase-in-Line (\x1b[K)
public struct TerminalLineStreamProcessor {
    private enum EscapeState {
        case normal
        case escape
        case csi(params: String)
        case osc(prevWasEsc: Bool)
        case charset
    }
    
    public struct CompletedLine {
        public let text: String
        public let timestamp: Date
    }
    
    private var utf8PendingBytes: [UInt8] = []
    private var escapeState: EscapeState = .normal
    private var currentLineChars: [Character] = []
    private var cursorIndex: Int = 0
    private var currentLineStartTime: Date?
    
    public init() {}
    
    /// Current un-terminated line text (e.g. an interactive prompt waiting for input).
    public var pendingLineText: String {
        String(currentLineChars)
    }
    
    /// Feeds raw bytes from a terminal/serial stream and returns any newly completed lines.
    public mutating func processBytes(_ bytes: ArraySlice<UInt8>, now: Date = Date()) -> [CompletedLine] {
        guard !bytes.isEmpty else { return [] }
        
        var combined: [UInt8]
        if utf8PendingBytes.isEmpty {
            combined = Array(bytes)
        } else {
            combined = utf8PendingBytes
            combined.append(contentsOf: bytes)
            utf8PendingBytes.removeAll(keepingCapacity: true)
        }
        
        // Hold back any incomplete trailing UTF-8 sequence for the next chunk
        let validPrefixCount = Self.validUTF8PrefixLength(combined)
        if validPrefixCount < combined.count {
            utf8PendingBytes = Array(combined[validPrefixCount...])
            combined.removeLast(combined.count - validPrefixCount)
        }
        
        guard !combined.isEmpty else { return [] }
        let decoded = String(decoding: combined, as: UTF8.self)
        return processString(decoded, now: now)
    }
    
    /// Feeds a string chunk and returns any newly completed lines.
    public mutating func processString(_ chunk: String, now: Date = Date()) -> [CompletedLine] {
        guard !chunk.isEmpty else { return [] }
        var completed: [CompletedLine] = []
        
        for scalar in chunk.unicodeScalars {
            let value = scalar.value
            
            switch escapeState {
            case .normal:
                if value == 0x1B { // ESC
                    escapeState = .escape
                } else if value == 0x0D { // \r (Carriage Return) -> move cursor to column 0
                    cursorIndex = 0
                } else if value == 0x0A { // \n (Line Feed) -> finalize current line
                    let lineText = String(currentLineChars)
                    let ts = currentLineStartTime ?? now
                    completed.append(CompletedLine(text: lineText, timestamp: ts))
                    currentLineChars.removeAll(keepingCapacity: true)
                    cursorIndex = 0
                    currentLineStartTime = nil
                } else if value == 0x08 { // \b (Backspace) -> move cursor left
                    if cursorIndex > 0 {
                        cursorIndex -= 1
                    }
                } else if value == 0x7F { // DEL -> delete char before cursor
                    if cursorIndex > 0 {
                        cursorIndex -= 1
                        if cursorIndex < currentLineChars.count {
                            currentLineChars.remove(at: cursorIndex)
                        }
                    }
                } else if value == 0x09 || value >= 0x20 { // Printable char or Tab
                    if currentLineStartTime == nil {
                        currentLineStartTime = now
                    }
                    let ch = Character(scalar)
                    if cursorIndex < currentLineChars.count {
                        currentLineChars[cursorIndex] = ch
                    } else {
                        currentLineChars.append(ch)
                    }
                    cursorIndex += 1
                } else {
                    // Ignore other non-printable control characters (0x00...0x07, 0x0B, 0x0C, 0x0E...0x1A, 0x1C...0x1F)
                }
                
            case .escape:
                if value == 0x5B { // '[' -> CSI
                    escapeState = .csi(params: "")
                } else if value == 0x5D { // ']' -> OSC
                    escapeState = .osc(prevWasEsc: false)
                } else if value == 0x28 || value == 0x29 || value == 0x2A || value == 0x2B { // (, ), *, +
                    escapeState = .charset
                } else {
                    // 2-byte ESC sequence consumed
                    escapeState = .normal
                }
                
            case .charset:
                escapeState = .normal
                
            case .csi(var params):
                if (0x40...0x7E).contains(value) {
                    // Final byte of CSI sequence
                    if value == 0x4B { // 'K' -> Erase in Line (EL)
                        let trimmed = params.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || trimmed == "0" {
                            // Erase from cursor to end of line
                            if cursorIndex < currentLineChars.count {
                                currentLineChars.removeSubrange(cursorIndex..<currentLineChars.count)
                            }
                        } else if trimmed == "2" {
                            // Erase entire line
                            currentLineChars.removeAll(keepingCapacity: true)
                            cursorIndex = 0
                        }
                    }
                    escapeState = .normal
                } else if params.count < 64 {
                    params.append(Character(scalar))
                    escapeState = .csi(params: params)
                } else {
                    // Safety bailout on malformed/unterminated CSI
                    escapeState = .normal
                }
                
            case .osc(let prevWasEsc):
                if value == 0x07 { // BEL terminates OSC
                    escapeState = .normal
                } else if prevWasEsc && value == 0x5C { // ESC \ (ST) terminates OSC
                    escapeState = .normal
                } else {
                    escapeState = .osc(prevWasEsc: value == 0x1B)
                }
            }
        }
        
        return completed
    }
    
    /// Flushes any remaining partial line (e.g. when stopping recording at a prompt).
    public mutating func flushPendingLine(now: Date = Date()) -> CompletedLine? {
        if !utf8PendingBytes.isEmpty {
            let leftover = String(decoding: utf8PendingBytes, as: UTF8.self)
            utf8PendingBytes.removeAll()
            _ = processString(leftover, now: now)
        }
        guard !currentLineChars.isEmpty else { return nil }
        let line = CompletedLine(text: String(currentLineChars), timestamp: currentLineStartTime ?? now)
        currentLineChars.removeAll()
        cursorIndex = 0
        currentLineStartTime = nil
        return line
    }
    
    /// Determines how many leading bytes form complete UTF-8 code points (holding back 1..3 trailing incomplete bytes).
    private static func validUTF8PrefixLength(_ bytes: [UInt8]) -> Int {
        let count = bytes.count
        guard count > 0 else { return 0 }
        
        // Check up to the last 3 bytes for an incomplete multi-byte UTF-8 start byte
        let checkLimit = min(3, count)
        for back in 1...checkLimit {
            let idx = count - back
            let b = bytes[idx]
            if b < 0x80 {
                // ASCII byte -> everything up to count is complete
                return count
            } else if (b & 0xC0) == 0xC0 {
                // Found a UTF-8 leading byte; determine its expected total byte length
                let expectedLength: Int
                if (b & 0xE0) == 0xC0 {
                    expectedLength = 2
                } else if (b & 0xF0) == 0xE0 {
                    expectedLength = 3
                } else if (b & 0xF8) == 0xF0 {
                    expectedLength = 4
                } else {
                    // Invalid lead byte; don't hold it back
                    return count
                }
                return (back < expectedLength) ? idx : count
            }
        }
        return count
    }
}
