import Foundation

public final class DataRedactor: @unchecked Sendable {
    public static let shared = DataRedactor()
    
    private struct RedactionRule {
        let pattern: String
        let replacement: String
    }
    
    private let rules: [RedactionRule] = [
        // Private keys
        RedactionRule(
            pattern: #"-----BEGIN (?:[A-Z0-9 ]+)?PRIVATE KEY-----[\s\S]*?-----END (?:[A-Z0-9 ]+)?PRIVATE KEY-----"#,
            replacement: "[REDACTED_PRIVATE_KEY]"
        ),
        // Passwords in flags or assignments (-p password, --password=xxx, password: xxx)
        RedactionRule(
            pattern: #"(?i)(?:-p\s+|--password[=:\s]+|password[=:\s]+|passwd[=:\s]+|secret[=:\s]+|token[=:\s]+|api[_-]?key[=:\s]+)(["']?)([^\s"'\n]+)\1"#,
            replacement: "$1[REDACTED_SECRET]$1"
        ),
        // Bearer tokens
        RedactionRule(
            pattern: #"Bearer\s+[A-Za-z0-9_\-\.]{20,}"#,
            replacement: "Bearer [REDACTED_BEARER_TOKEN]"
        ),
        // Database connection strings
        RedactionRule(
            pattern: #"(?:postgres|mysql|mongodb|redis):\/\/[^:\s\n]+:([^@\s\n]+)@"#,
            replacement: "db://[REDACTED_USER]:[REDACTED_PASS]@"
        ),
        // AWS Secret Keys
        RedactionRule(
            pattern: #"(?i)aws_secret_access_key[=:\s]+[A-Za-z0-9\/+=]{40}"#,
            replacement: "aws_secret_access_key=[REDACTED_AWS_SECRET]"
        )
    ]
    
    public init() {}
    
    public func redact(_ text: String) -> String {
        var sanitized = text
        for rule in rules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    options: [],
                    range: NSRange(location: 0, length: (sanitized as NSString).length),
                    withTemplate: rule.replacement
                )
            }
        }
        return sanitized
    }
}
