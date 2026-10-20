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
    @State private var hoveredItemId: String?
    
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
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                
                TextField("快速跳转会话、切换主题、或输入运维指令 (ESC 退出)...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isInputFocused)
                    .onSubmit {
                        HapticFeedbackHelper.shared.performGeneric()
                        handlePrimaryAction()
                    }
                
                if !query.isEmpty {
                    Button(action: {
                        HapticFeedbackHelper.shared.performGeneric()
                        query = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.clear)
            
            Divider()
            
            // Results List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    openTabsSection
                    savedSessionsSection
                    themesSection
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
        .onAppear {
            isInputFocused = true
        }
    }
    
    @ViewBuilder
    private var openTabsSection: some View {
        if !openTabs.isEmpty {
            let matches = openTabs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            if !matches.isEmpty {
                Text("当前已打开的标签页")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                
                ForEach(matches) { tab in
                    PaletteTabRow(
                        tab: tab,
                        isHovered: hoveredItemId == tab.id.uuidString,
                        onSelect: {
                            HapticFeedbackHelper.shared.performGeneric()
                            onSelectTab(tab.id)
                            onClose()
                        },
                        onHover: { h in hoveredItemId = h ? tab.id.uuidString : nil }
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private var savedSessionsSection: some View {
        if !filteredSessions.isEmpty {
            Text("所有保存的连接与设备")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)
            
            ForEach(Array(filteredSessions.prefix(8))) { sess in
                PaletteSessionRow(
                    session: sess,
                    isHovered: hoveredItemId == sess.id.uuidString,
                    onSelect: {
                        HapticFeedbackHelper.shared.performGeneric()
                        onOpenSession(sess)
                        onClose()
                    },
                    onHover: { h in hoveredItemId = h ? sess.id.uuidString : nil }
                )
            }
        }
    }
    
    @ViewBuilder
    private var themesSection: some View {
        if query.localizedCaseInsensitiveContains("theme") || query.localizedCaseInsensitiveContains("主题") || query.isEmpty {
            Text("极速切换终端主题")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)
            
            ForEach(TerminalTheme.allThemes, id: \.id) { theme in
                PaletteThemeRow(
                    theme: theme,
                    isCurrent: theme.id == themeStore.currentTheme.id,
                    isHovered: hoveredItemId == theme.id,
                    onSelect: {
                        selectTheme(theme)
                    },
                    onHover: { h in hoveredItemId = h ? theme.id : nil }
                )
            }
        }
    }
    
    private func selectTheme(_ theme: TerminalTheme) {
        HapticFeedbackHelper.shared.performGeneric()
        themeStore.setTheme(theme)
        onClose()
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

// MARK: - Palette Row Components
private struct PaletteTabRow: View {
    let tab: WorkspaceTab
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: tab.session.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("活动 • \(tab.uptimeFormatted)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .padding(.horizontal, 6)
    }
}

private struct PaletteSessionRow: View {
    let session: SessionItem
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: session.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name)
                        .font(.system(size: 12, weight: .medium))
                    Text("\(session.protocolType.rawValue) • \(session.host):\(session.port)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("回车启动")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .padding(.horizontal, 6)
    }
}

private struct PaletteThemeRow: View {
    let theme: TerminalTheme
    let isCurrent: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(nsColor: theme.cursorColor))
                    .frame(width: 8, height: 8)
                Text(theme.name)
                    .font(.system(size: 12))
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .padding(.horizontal, 6)
    }
}
