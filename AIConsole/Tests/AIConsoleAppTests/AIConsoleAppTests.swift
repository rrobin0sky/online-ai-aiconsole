import XCTest
@testable import AIConsoleApp
import Foundation

final class AIConsoleAppTests: XCTestCase {
    func testKeychainHelper() {
        let key = "test_key_\(UUID().uuidString)"
        let secret = "SuperSecretPassword123"
        
        let saved = KeychainHelper.shared.save(key: key, secret: secret)
        XCTAssertTrue(saved)
        
        let readVal = KeychainHelper.shared.read(key: key)
        XCTAssertEqual(readVal, secret)
        
        KeychainHelper.shared.delete(key: key)
        let afterDelete = KeychainHelper.shared.read(key: key)
        XCTAssertNil(afterDelete)
    }
    
    func testSessionItemSerialization() throws {
        let item = SessionItem(
            name: "Test SSH Session",
            protocolType: .ssh,
            host: "192.168.1.1",
            port: 22,
            username: "admin"
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(SessionItem.self, from: data)
        XCTAssertEqual(decoded.name, item.name)
        XCTAssertEqual(decoded.host, item.host)
        XCTAssertEqual(decoded.port, 22)
    }
    
    func testThemesAvailable() {
        XCTAssertFalse(TerminalTheme.allThemes.isEmpty)
        XCTAssertEqual(TerminalTheme.defaultTheme.ansiHexColors.count, 16)
        XCTAssertEqual(TerminalTheme.defaultTheme.backgroundHex, "#16161E")
    }
    
    func testDataRedactor() {
        let rawLog = """
        Connecting to postgres://admin:superSecret123@192.168.1.50:5432/prod_db
        Running command: curl -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.secretToken12345"
        """
        let redacted = DataRedactor.shared.redact(rawLog)
        XCTAssertFalse(redacted.contains("superSecret123"))
        XCTAssertFalse(redacted.contains("secretToken12345"))
        XCTAssertTrue(redacted.contains("[REDACTED_PASS]"))
        XCTAssertTrue(redacted.contains("[REDACTED_BEARER_TOKEN]"))
    }
    
    @MainActor
    func testAIServiceCardParsing() {
        let service = AIService()
        let cautionMarkdown = """
        建议重启服务：
        ```bash
        systemctl restart nginx
        ```
        """
        let cautionCards = service.parseCommandCards(from: cautionMarkdown)
        XCTAssertEqual(cautionCards.count, 1)
        XCTAssertEqual(cautionCards.first?.riskLevel, .caution)
        
        let dangerousMarkdown = """
        根据报错，建议彻底清理目录：
        ```bash
        rm -rf /var/log/nginx/old.log
        ```
        """
        let dangerousCards = service.parseCommandCards(from: dangerousMarkdown)
        XCTAssertEqual(dangerousCards.count, 1)
        XCTAssertEqual(dangerousCards.first?.riskLevel, .dangerous)
        
        let dangerousEval = service.evaluateRisk(command: "rm -rf / && reboot")
        XCTAssertEqual(dangerousEval, .dangerous)
        
        let safeEval = service.evaluateRisk(command: "ls -la /var/log")
        XCTAssertEqual(safeEval, .safe)
    }
}
