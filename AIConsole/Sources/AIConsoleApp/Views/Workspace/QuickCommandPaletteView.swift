import SwiftUI

public struct QuickCommandPaletteView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var themeStore: ThemeStore = .shared
    let openTabs: [WorkspaceTab]
    let onSelectTab: (UUID) -> Void
    let onOpenSession: (SessionItem) -> Void
    let onExecuteCommand: (String) -> Void
    let onClose: () -> Void
    
    @State private var query: String = ""
    @FocusState private var isInputFocused: Bool
    
    private var allSessions: [SessionItem] {
        var list: [SessionItem] = []
        func collect(items: [SessionItem]) {
            for item in items {
                if item.isGroup {
                    if let children = item.children { collect(items: children) }
                } else {
                    list.append(item)
                }
            }
        }
        collect(items: sessionStore.rootItems)
        return list
    }
    
    private var filteredSessions: [SessionItem] {
        if query.isEmpty { return allSessions }
        return allSessions.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.host.localizedCaseInsensitiveContains(query) ||
            $0.protocolType.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar (Spotlight Style)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                
                TextField("快速跳转会话、切换主题、或输入运维指令 (ESC 退出)...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isInputFocused)
                    .onSubmit {
                        handlePrimaryAction()
                    }
                
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Results List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // 1. Open Tabs Section
                    if !openTabs.isEmpty {
                        Text("当前已打开的标签页")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        
                        ForEach(openTabs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { tab in
                            Button(action: {
                                onSelectTab(tab.id)
                                onClose()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: tab.session.iconName)
                                        .foregroundColor(.green)
                                    Text(tab.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("活动标签 • \(tab.uptimeFormatted)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // 2. Saved Sessions Section
                    if !filteredSessions.isEmpty {
                        Text("所有保存的连接与设备")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        
                        ForEach(filteredSessions.prefix(8)) { sess in
                            Button(action: {
                                onOpenSession(sess)
                                onClose()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: sess.iconName)
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sess.name)
                                            .font(.system(size: 13, weight: .medium))
                                        Text("\(sess.protocolType.rawValue) • \(sess.host):\(sess.port)")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("回车启动")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // 3. Quick Themes Switcher
                    if query.localizedCaseInsensitiveContains("theme") || query.localizedCaseInsensitiveContains("主题") || query.isEmpty {
                        Text("极速切换终端主题")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        
                        ForEach(TerminalTheme.allThemes) { theme in
                            Button(action: {
                                themeStore.setTheme(theme)
                                onClose()
                            }) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(nsColor: theme.cursorColor))
                                        .frame(width: 10, height: 10)
                                    Text(theme.name)
                                        .font(.system(size: 12))
                                    Spacer()
                                    if theme.id == themeStore.currentTheme.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 540)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
        .onAppear {
            isInputFocused = true
        }
    }
    
    private func handlePrimaryAction() {
        if let firstTab = openTabs.first(where: { $0.title.localizedCaseInsensitiveContains(query) }) {
            onSelectTab(firstTab.id)
            onClose()
        } else if let firstSession = filteredSessions.first {
            onOpenSession(firstSession)
            onClose()
        } else if !query.isEmpty {
            onExecuteCommand(query)
            onClose()
        }
    }
}
