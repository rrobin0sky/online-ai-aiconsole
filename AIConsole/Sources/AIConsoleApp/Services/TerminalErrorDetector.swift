import Foundation
import Combine

public struct DetectedErrorEvent: Identifiable {
    public let id = UUID()
    public let summary: String
    public let contextSnippet: String
    public let timestamp: Date
    
    public init(summary: String, contextSnippet: String, timestamp: Date = Date()) {
        self.summary = summary
        self.contextSnippet = contextSnippet
        self.timestamp = timestamp
    }
}

public final class TerminalErrorDetector: @unchecked Sendable {
    public static let shared = TerminalErrorDetector()
    
    private let errorRegexes: [NSRegularExpression]
    private var lastTriggerTime: Date = Date.distantPast
    private let throttleInterval: TimeInterval = 3.0
    
    public var onErrorDetected: ((DetectedErrorEvent) -> Void)?
    
    public init() {
        let patterns = [
            #"(?i)\b(command not found|permission denied|no such file or directory|access denied|connection refused|connection timed? out|network is unreachable|host is down|address already in use|broken pipe|segmentation fault|core dumped|fatal error|panic:|traceback \(most recent call last\):)\b"#,
            #"(?i)\b(err-disabled|administratively down|input errors?|output errors?|crc errors?|packet loss)\b"#,
            #"(?i)\b(host key verification failed|unable to negotiate with|no matching (host key|key exchange|cipher|mac)|remote host identification has changed|kex_exchange_identification|connection closed by remote host)\b"#,
            #"(?m)^(?:\s*%\s*)?(?:Invalid input|Incomplete command|Ambiguous command|Error|Failed|Failure|Critical|Alarm|Unrecognized command)[^\r\n]*"#
        ]
        
        var compiled: [NSRegularExpression] = []
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: []) {
                compiled.append(regex)
            }
        }
        self.errorRegexes = compiled
    }
    
    public func processOutput(chunk: String, fullBufferProvider: @escaping () -> String) {
        guard !chunk.isEmpty else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) > throttleInterval else { return }
        
        let nsChunk = chunk as NSString
        let range = NSRange(location: 0, length: nsChunk.length)
        
        for regex in errorRegexes {
            if let match = regex.firstMatch(in: chunk, options: [], range: range) {
                let matchedText = nsChunk.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastTriggerTime = now
                
                DispatchQueue.main.async { [weak self] in
                    let fullContext = fullBufferProvider()
                    let event = DetectedErrorEvent(
                        summary: matchedText.isEmpty ? "终端输出报错异常" : matchedText,
                        contextSnippet: fullContext
                    )
                    self?.onErrorDetected?(event)
                }
                break
            }
        }
    }
}
