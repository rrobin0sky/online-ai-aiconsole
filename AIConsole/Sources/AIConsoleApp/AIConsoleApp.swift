import SwiftUI
import AppKit

@main
struct AIConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainWorkspaceView()
                .frame(minWidth: 1050, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // App Core Menu (Settings)
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置与模型配置...") {
                    NotificationCenter.default.post(name: .AIConsoleOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // App Info (About)
            CommandGroup(replacing: .appInfo) {
                Button("关于智能运维终端") {
                    showAboutPanel()
                }
            }
            
            // File / Session Menu
            CommandGroup(replacing: .newItem) {
                Button("新建会话...") {
                    NotificationCenter.default.post(name: .AIConsoleNewSessionDialog, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("新建会话 (Cmd+N)...") {
                    NotificationCenter.default.post(name: .AIConsoleNewSessionDialog, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("新建分组...") {
                    NotificationCenter.default.post(name: .AIConsoleNewGroupDialog, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.shift, .command])
                
                Button("启动本地终端") {
                    NotificationCenter.default.post(name: .AIConsoleNewTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.shift, .command])
                
                Divider()
                
                Button("导入会话配置...") {
                    NotificationCenter.default.post(name: .AIConsoleImportConfig, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("备份导出配置 (含凭据)...") {
                    NotificationCenter.default.post(name: .AIConsoleExportConfig, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.shift, .command])
                
                Divider()
                
                Button("关闭当前标签页") {
                    NotificationCenter.default.post(name: .AIConsoleCloseTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Button("关闭所有标签页") {
                    NotificationCenter.default.post(name: .AIConsoleCloseAllTabs, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.option, .command])
            }
            
            // Edit Menu Additions
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("清空当前终端屏幕") {
                    NotificationCenter.default.post(name: .AIConsoleClearTerminal, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            
            // View & Layout Menu
            CommandGroup(after: .toolbar) {
                Divider()
                Button("开启 / 关闭多终端同步广播") {
                    NotificationCenter.default.post(name: .AIConsoleToggleBroadcast, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.shift, .command])
                
                Divider()
                
                Button("展开 / 收起智能助手") {
                    NotificationCenter.default.post(name: .AIConsoleToggleAIPanel, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.option, .command])
                
                Button("展开 / 收起常用命令库") {
                    NotificationCenter.default.post(name: .AIConsoleToggleSnippetsPanel, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.option, .command])
                
                Divider()
                
                Button("切换到下一个标签页") {
                    NotificationCenter.default.post(name: .AIConsoleNextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.shift, .command])
                
                Button("切换到上一个标签页") {
                    NotificationCenter.default.post(name: .AIConsolePrevTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.shift, .command])
            }
            
            // AI Copilot Menu
            CommandMenu("智能运维诊断") {
                Button("提取当前终端上下文智能诊断") {
                    NotificationCenter.default.post(name: .AIConsoleDiagnoseCurrent, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.option, .command])
                
                Button("🌐 联合诊断所有同网络节点") {
                    NotificationCenter.default.post(name: .AIConsoleDiagnoseCluster, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.option, .shift, .command])
                
                Divider()
                
                Button("停止当前智能生成") {
                    NotificationCenter.default.post(name: .AIConsoleCancelAIGeneration, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)
                
                Button("清空智能对话历史") {
                    NotificationCenter.default.post(name: .AIConsoleClearAIChat, object: nil)
                }
                
                Divider()
                
                Button("配置大模型接口与服务商...") {
                    NotificationCenter.default.post(name: .AIConsoleOpenSettings, object: nil)
                }
            }
            
            // Help Menu
            CommandGroup(replacing: .help) {
                Button("快捷键速查与快速入门") {
                    showHelpPanel()
                }
                
                Divider()
                
                Button("安全脱敏与系统钥匙串说明") {
                    showSecurityInfoPanel()
                }
            }
        }
    }
    
    private func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "智能运维终端工作台 (AI Console)"
        alert.informativeText = """
        版本: 2.0.0 旗舰版
        系统支持: macOS 14.0+ (Apple Silicon 原生优化)
        
        功能特性:
        • 多协议支持: 终端远程连接、远程桌面控制、串行硬件接口、安全文件传输
        • 智能运维排障: 异常实时感知、流式传输诊断、同网段多节点联合分析
        • 原生硬件级安全: Apple 官方 Keychain Services 隔离存储、Touch ID 生物认证保护
        • 批量集群运维: ⚡ 同步多播广播控制中心、全键盘击键实时镜像
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func showHelpPanel() {
        let alert = NSAlert()
        alert.messageText = "常用快捷键速查指南"
        alert.informativeText = """
        【会话与标签】
        • ⌘ + T / ⌘ + N : 调出新建会话配置对话框
        • ⇧ + ⌘ + T : 极速启动本地终端
        • ⌘ + W / ⌥ + ⌘ + W : 关闭当前标签页 / 关闭所有标签页
        • ⇧ + ⌘ + [ / ] : 切换上一个 / 下一个标签页
        • ⇧ + ⌘ + N : 新建分组目录
        
        【运维与广播】
        • ⇧ + ⌘ + B : 开启 / 关闭 多终端同步广播控制中心
        • ⌘ + K : 清空当前终端屏幕
        • ⌥ + ⌘ + S : 展开 / 收起 常用运维命令库
        
        【智能排障】
        • ⌥ + ⌘ + D : 提取当前终端上下文进行智能诊断
        • ⌥ + ⇧ + ⌘ + D : 联合诊断所有同网络节点
        • ⌘ + . : 停止当前智能生成
        • ⌘ + , : 打开大模型参数与密钥配置
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func showSecurityInfoPanel() {
        let alert = NSAlert()
        alert.messageText = "安全与数据隐私保护说明"
        alert.informativeText = """
        • Apple Keychain 原生隔离: 你的 SSH 密码、私钥、AI API Key 均受 macOS 系统级 Keychain Services 与 Secure Enclave 芯片硬件加密保护。
        • Touch ID 生物识别: 敏感凭据查看、配置导出受 Touch ID 指纹鉴权守护。
        • 实时数据脱敏: 发送给大模型的日志会自动脱敏密码、Token、数据库连接串与私钥。
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
}

// MARK: - Notification Names for App Menus
extension Notification.Name {
    static let AIConsoleNewTab = Notification.Name("AIConsoleNewTab")
    static let AIConsoleCloseTab = Notification.Name("AIConsoleCloseTab")
    static let AIConsoleCloseAllTabs = Notification.Name("AIConsoleCloseAllTabs")
    static let AIConsoleNewSessionDialog = Notification.Name("AIConsoleNewSessionDialog")
    static let AIConsoleNewGroupDialog = Notification.Name("AIConsoleNewGroupDialog")
    static let AIConsoleImportConfig = Notification.Name("AIConsoleImportConfig")
    static let AIConsoleExportConfig = Notification.Name("AIConsoleExportConfig")
    static let AIConsoleClearTerminal = Notification.Name("AIConsoleClearTerminal")
    static let AIConsoleToggleBroadcast = Notification.Name("AIConsoleToggleBroadcast")
    static let AIConsoleToggleAIPanel = Notification.Name("AIConsoleToggleAIPanel")
    static let AIConsoleToggleSnippetsPanel = Notification.Name("AIConsoleToggleSnippetsPanel")
    static let AIConsoleNextTab = Notification.Name("AIConsoleNextTab")
    static let AIConsolePrevTab = Notification.Name("AIConsolePrevTab")
    static let AIConsoleDiagnoseCurrent = Notification.Name("AIConsoleDiagnoseCurrent")
    static let AIConsoleDiagnoseCluster = Notification.Name("AIConsoleDiagnoseCluster")
    static let AIConsoleCancelAIGeneration = Notification.Name("AIConsoleCancelAIGeneration")
    static let AIConsoleClearAIChat = Notification.Name("AIConsoleClearAIChat")
    static let AIConsoleOpenSettings = Notification.Name("AIConsoleOpenSettings")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
