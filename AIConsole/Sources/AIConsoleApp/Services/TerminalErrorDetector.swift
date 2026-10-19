import Foundation
import Combine

public struct DetectedErrorEvent: Identifiable {
    public let id = UUID()
    public let tabId: UUID?
    public let summary: String
    public let contextSnippet: String
    public let timestamp: Date
    
    public init(tabId: UUID? = nil, summary: String, contextSnippet: String, timestamp: Date = Date()) {
        self.tabId = tabId
        self.summary = summary
        self.contextSnippet = contextSnippet
        self.timestamp = timestamp
    }
}

public final class TerminalErrorDetector: @unchecked Sendable {
    public static let shared = TerminalErrorDetector()
    
    private let errorRegexes: [NSRegularExpression]
    private var lastTriggerTimes: [UUID: Date] = [:]
    private var globalLastTriggerTime: Date = Date.distantPast
    private let throttleInterval: TimeInterval = 3.0
    private let lock = NSLock()
    
    // Per-tab event listeners to prevent cross-tab event collisions
    private var listeners: [UUID: (DetectedErrorEvent) -> Void] = [:]
    
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
    
    public func registerListener(for tabId: UUID, handler: @escaping (DetectedErrorEvent) -> Void) {
        lock.lock()
        listeners[tabId] = handler
        lock.unlock()
    }
    
    public func unregisterListener(for tabId: UUID) {
        lock.lock()
        listeners.removeValue(forKey: tabId)
        lastTriggerTimes.removeValue(forKey: tabId)
        lock.unlock()
    }
    
    public func processOutput(tabId: UUID?, chunk: String, fullBufferProvider: @escaping () -> String) {
        guard !chunk.isEmpty else { return }
        
        let now = Date()
        lock.lock()
        if let tid = tabId {
            if let last = lastTriggerTimes[tid], now.timeIntervalSince(last) < throttleInterval {
                lock.unlock()
                return
            }
        } else {
            if now.timeIntervalSince(globalLastTriggerTime) < throttleInterval {
                lock.unlock()
                return
            }
        }
        lock.unlock()
        
        let nsChunk = chunk as NSString
        let range = NSRange(location: 0, length: nsChunk.length)
        
        for regex in errorRegexes {
            if let match = regex.firstMatch(in: chunk, options: [], range: range) {
                let matchedText = nsChunk.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                
                lock.lock()
                if let tid = tabId {
                    lastTriggerTimes[tid] = now
                } else {
                    globalLastTriggerTime = now
                }
                let targetHandler = tabId != nil ? listeners[tabId!] : nil
                let allHandlers = Array(listeners.values)
                lock.unlock()
                
                DispatchQueue.main.async {
                    let fullContext = fullBufferProvider()
                    let event = DetectedErrorEvent(
                        tabId: tabId,
                        summary: matchedText.isEmpty ? "终端输出报错异常" : matchedText,
                        contextSnippet: fullContext
                    )
                    
                    if let handler = targetHandler {
                        handler(event)
                    } else if tabId == nil {
                        for h in allHandlers {
                            h(event)
                        }
                    }
                }
                break
            }
        }
    }
}
