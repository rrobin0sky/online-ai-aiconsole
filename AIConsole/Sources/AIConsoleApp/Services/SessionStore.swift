import Foundation
import Combine
import AppKit

public struct ExportableSessionItem: Codable {
    public var item: SessionItem
    public var passwordSecret: String?
    public var children: [ExportableSessionItem]?
    
    public init(item: SessionItem, passwordSecret: String? = nil, children: [ExportableSessionItem]? = nil) {
        self.item = item
        self.passwordSecret = passwordSecret
        self.children = children
    }
}

public struct ExportableSessionBundle: Codable {
    public let app: String
    public let version: String
    public let exportDate: Date
    public let sessions: [ExportableSessionItem]
    
    public init(sessions: [ExportableSessionItem]) {
        self.app = "AIConsole"
        self.version = "1.0.0"
        self.exportDate = Date()
        self.sessions = sessions
    }
}

@MainActor
public final class SessionStore: ObservableObject {
    public static let shared = SessionStore()
    
    @Published public var rootItems: [SessionItem] = []
    @Published public var selectedItem: SessionItem?
    
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AIConsole", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("sessions.json")
        
        load()
        
        if rootItems.isEmpty {
            createDefaultSampleSessions()
        }
    }
    
    public func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([SessionItem].self, from: data) else {
            return
        }
        self.rootItems = items
    }
    
    public func save() {
        guard let data = try? JSONEncoder().encode(rootItems) else { return }
        try? data.write(to: fileURL)
    }
    
    public func addSession(_ item: SessionItem, parentGroupId: UUID? = nil) {
        if let parentId = parentGroupId {
            rootItems = insertItem(item, into: rootItems, parentId: parentId)
        } else {
            rootItems.append(item)
        }
        save()
    }
    
    public func updateSession(_ item: SessionItem) {
        rootItems = updateItemInList(item, items: rootItems)
        save()
    }
    
    public func saveOrMoveSession(_ item: SessionItem, newParentId: UUID?) {
        // 1. Remove from old position if exists
        rootItems = deleteItemFromList(id: item.id, items: rootItems)
        // 2. Insert into new parent or root
        if let parentId = newParentId {
            rootItems = insertItem(item, into: rootItems, parentId: parentId)
        } else {
            rootItems.append(item)
        }
        save()
    }
    
    public func deleteSession(id: UUID) {
        rootItems = deleteItemFromList(id: id, items: rootItems)
        if selectedItem?.id == id {
            selectedItem = nil
        }
        save()
    }
    
    // MARK: - Export & Import with Credentials
    
    public func exportSessionsToJSONData() -> Data? {
        let exportableList = buildExportableItems(items: rootItems)
        let bundle = ExportableSessionBundle(sessions: exportableList)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(bundle)
    }
    
    public func importSessionsFromJSONData(_ data: Data) -> (success: Bool, count: Int, error: String?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Try decoding bundle first
        if let bundle = try? decoder.decode(ExportableSessionBundle.self, from: data) {
            let (restored, count) = restoreItemsFromExportable(bundle.sessions)
            self.rootItems.append(contentsOf: restored)
            save()
            return (true, count, nil)
        }
        
        // Or legacy array format
        if let legacyItems = try? decoder.decode([SessionItem].self, from: data) {
            self.rootItems.append(contentsOf: legacyItems)
            save()
            return (true, legacyItems.count, nil)
        }
        
        return (false, 0, "无法解析导入的文件，格式不匹配。")
    }
    
    public func exportToFileWithSavePanel() {
        Task { @MainActor in
            let authenticated = await BiometricGuard.shared.authenticate(reason: "导出包含密码与凭据的完整会话配置")
            guard authenticated else {
                HapticFeedbackHelper.shared.performLevelChange()
                return
            }
            HapticFeedbackHelper.shared.performGeneric()
            
            let savePanel = NSSavePanel()
            savePanel.title = "导出所有会话配置 (含凭据)"
            savePanel.prompt = "导出"
            savePanel.allowedContentTypes = [.json]
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            savePanel.nameFieldStringValue = "AIConsole-Sessions-Backup-\(formatter.string(from: Date())).json"
            
            savePanel.begin { [weak self] result in
                guard result == .OK, let url = savePanel.url, let self = self else { return }
                if let data = self.exportSessionsToJSONData() {
                    try? data.write(to: url)
                    HapticFeedbackHelper.shared.performAlignment()
                    let alert = NSAlert()
                    alert.messageText = "导出成功"
                    alert.informativeText = "所有分组、会话与账号密码已安全导出至：\n\(url.path)"
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            }
        }
    }
    
    public func importFromFileWithOpenPanel() {
        let openPanel = NSOpenPanel()
        openPanel.title = "导入会话配置"
        openPanel.prompt = "导入"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.json]
        
        openPanel.begin { [weak self] result in
            guard result == .OK, let url = openPanel.url, let self = self else { return }
            if let data = try? Data(contentsOf: url) {
                let res = self.importSessionsFromJSONData(data)
                let alert = NSAlert()
                if res.success {
                    alert.messageText = "导入成功"
                    alert.informativeText = "成功导入了 \(res.count) 个会话/分组，相关账号密码已恢复到系统 Keychain。"
                    alert.alertStyle = .informational
                } else {
                    alert.messageText = "导入失败"
                    alert.informativeText = res.error ?? "未知错误"
                    alert.alertStyle = .critical
                }
                alert.runModal()
            }
        }
    }
    
    private func buildExportableItems(items: [SessionItem]) -> [ExportableSessionItem] {
        var exportableList: [ExportableSessionItem] = []
        for item in items {
            let secret = KeychainHelper.shared.read(key: item.credentialKey)
            var childrenExport: [ExportableSessionItem]? = nil
            if let children = item.children {
                childrenExport = buildExportableItems(items: children)
            }
            let exp = ExportableSessionItem(item: item, passwordSecret: secret, children: childrenExport)
            exportableList.append(exp)
        }
        return exportableList
    }
    
    private func restoreItemsFromExportable(_ exportableItems: [ExportableSessionItem]) -> (items: [SessionItem], totalCount: Int) {
        var restoredList: [SessionItem] = []
        var total = 0
        
        for exp in exportableItems {
            var item = exp.item
            // Ensure unique ID on import to avoid conflicts
            item.id = UUID()
            let newCredKey = UUID().uuidString
            item.credentialKey = newCredKey
            
            if let secret = exp.passwordSecret, !secret.isEmpty {
                KeychainHelper.shared.save(key: newCredKey, secret: secret)
            }
            
            if let children = exp.children {
                let (restoredChildren, count) = restoreItemsFromExportable(children)
                item.children = restoredChildren
                total += count
            }
            
            restoredList.append(item)
            total += 1
        }
        return (restoredList, total)
    }
    
    private func insertItem(_ item: SessionItem, into list: [SessionItem], parentId: UUID) -> [SessionItem] {
        var updated = list
        for i in 0..<updated.count {
            if updated[i].id == parentId {
                if updated[i].children == nil {
                    updated[i].children = []
                }
                updated[i].children?.append(item)
                return updated
            } else if let children = updated[i].children {
                updated[i].children = insertItem(item, into: children, parentId: parentId)
            }
        }
        return updated
    }
    
    private func updateItemInList(_ item: SessionItem, items: [SessionItem]) -> [SessionItem] {
        var updated = items
        for i in 0..<updated.count {
            if updated[i].id == item.id {
                updated[i] = item
                return updated
            } else if let children = updated[i].children {
                updated[i].children = updateItemInList(item, items: children)
            }
        }
        return updated
    }
    
    private func deleteItemFromList(id: UUID, items: [SessionItem]) -> [SessionItem] {
        var updated: [SessionItem] = []
        for var item in items {
            if item.id == id {
                continue
            }
            if let children = item.children {
                item.children = deleteItemFromList(id: id, items: children)
            }
            updated.append(item)
        }
        return updated
    }
    
    private func createDefaultSampleSessions() {
        let localFolder = SessionItem(
            name: "本地开发与串口",
            isGroup: true,
            iconName: "folder.fill",
            colorHex: "#89B4FA",
            children: [
                SessionItem(
                    name: "Local Shell (Zsh)",
                    iconName: "terminal.fill",
                    protocolType: .ssh,
                    host: "localhost",
                    username: NSUserName()
                ),
                SessionItem(
                    name: "USB Serial Debug (115200)",
                    iconName: "cable.connector",
                    protocolType: .serial,
                    serialDevicePath: "/dev/cu.usbserial",
                    baudRate: 115200
                )
            ]
        )
        
        let serverFolder = SessionItem(
            name: "远程生产服务器",
            isGroup: true,
            iconName: "server.rack",
            colorHex: "#A6E3A1",
            children: [
                SessionItem(
                    name: "Web Server 01",
                    iconName: "terminal.fill",
                    protocolType: .ssh,
                    host: "192.168.1.100",
                    username: "ubuntu"
                ),
                SessionItem(
                    name: "VNC Remote Desktop",
                    iconName: "display.2",
                    protocolType: .vnc,
                    host: "192.168.1.100",
                    port: 5900
                ),
                SessionItem(
                    name: "FTP File Server",
                    iconName: "folder.badge.gearshape",
                    protocolType: .ftp,
                    host: "192.168.1.100",
                    port: 21
                )
            ]
        )
        
        rootItems = [localFolder, serverFolder]
        save()
    }
}
