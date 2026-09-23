import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var sessionStore: SessionStore
    var onOpenSession: ((SessionItem) -> Void)?
    var onOpenAllInGroup: ((SessionItem) -> Void)?
    
    @State private var searchText = ""
    @State private var showingEditSheet = false
    @State private var editingTarget: SessionItem?
    @State private var parentGroupForNew: UUID?
    @State private var showingNewGroupDialog = false
    @State private var newGroupName = ""
    @State private var selectedSessionId: UUID?
    
    public init(
        sessionStore: SessionStore,
        onOpenSession: ((SessionItem) -> Void)? = nil,
        onOpenAllInGroup: ((SessionItem) -> Void)? = nil
    ) {
        self.sessionStore = sessionStore
        self.onOpenSession = onOpenSession
        self.onOpenAllInGroup = onOpenAllInGroup
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header / Search Bar & Quick Add Menu
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("搜索会话 (名称/IP/端口)...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                
                Menu {
                    Button(action: {
                        parentGroupForNew = nil
                        editingTarget = nil
                        showingEditSheet = true
                    }) {
                        Label("新建连接会话...", systemImage: "plus")
                    }
                    
                    Button(action: {
                        newGroupName = "新建分组"
                        showingNewGroupDialog = true
                    }) {
                        Label("新建目录/分组...", systemImage: "folder.badge.plus")
                    }
                    
                    Divider()
                    
                    Button(action: {
                        sessionStore.importFromFileWithOpenPanel()
                    }) {
                        Label("导入会话配置文件...", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(action: {
                        sessionStore.exportToFileWithSavePanel()
                    }) {
                        Label("备份导出配置...", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("添加会话或新建分组")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Collapsible Tree View
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let items = filteredItems(items: sessionStore.rootItems)
                    if items.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text(searchText.isEmpty ? "暂无会话，点击上方 + 新建" : "未找到匹配会话")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach(items, id: \.id) { item in
                            SessionTreeNodeView(
                                item: item,
                                selectedSessionId: $selectedSessionId,
                                sessionStore: sessionStore,
                                onOpen: { onOpenSession?($0) },
                                onOpenAllInGroup: { onOpenAllInGroup?($0) },
                                onEdit: { target in
                                    editingTarget = target
                                    parentGroupForNew = nil
                                    showingEditSheet = true
                                },
                                onAddChild: { parentId in
                                    parentGroupForNew = parentId
                                    editingTarget = nil
                                    showingEditSheet = true
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Bottom Action Bar
            HStack {
                Text("\(totalSessionCount(items: sessionStore.rootItems)) 个会话")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    parentGroupForNew = nil
                    editingTarget = nil
                    showingEditSheet = true
                }) {
                    Label("新建会话", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingEditSheet) {
            SessionEditSheet(
                sessionStore: sessionStore,
                editingItem: editingTarget,
                parentGroupId: parentGroupForNew
            )
        }
        .sheet(isPresented: $showingNewGroupDialog) {
            NewGroupSheet(sessionStore: sessionStore)
        }
    }
    
    private func totalSessionCount(items: [SessionItem]) -> Int {
        var count = 0
        for item in items {
            if item.isGroup {
                if let children = item.children {
                    count += totalSessionCount(items: children)
                }
            } else {
                count += 1
            }
        }
        return count
    }
    
    private func filteredItems(items: [SessionItem]) -> [SessionItem] {
        guard !searchText.isEmpty else { return items }
        var result: [SessionItem] = []
        for item in items {
            if item.isGroup {
                if let children = item.children {
                    let matched = filteredItems(items: children)
                    if !matched.isEmpty || item.name.localizedCaseInsensitiveContains(searchText) {
                        var group = item
                        group.children = matched
                        result.append(group)
                    }
                }
            } else {
                if item.name.localizedCaseInsensitiveContains(searchText) ||
                   item.host.localizedCaseInsensitiveContains(searchText) ||
                   item.username.localizedCaseInsensitiveContains(searchText) ||
                   String(item.port).contains(searchText) {
                    result.append(item)
                }
            }
        }
        return result
    }
}

// MARK: - Collapsible Tree Node View
struct SessionTreeNodeView: View {
    let item: SessionItem
    @Binding var selectedSessionId: UUID?
    @ObservedObject var sessionStore: SessionStore
    let onOpen: (SessionItem) -> Void
    let onOpenAllInGroup: (SessionItem) -> Void
    let onEdit: (SessionItem) -> Void
    let onAddChild: (UUID) -> Void
    
    @State private var isExpanded: Bool = true
    @State private var isHovered: Bool = false
    
    var body: some View {
        if item.isGroup {
            // Collapsible Folder / Group
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    
                    Image(systemName: item.iconName.isEmpty ? "folder.fill" : item.iconName)
                        .foregroundColor(.yellow)
                        .font(.system(size: 13))
                    
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let children = item.children {
                        Text("(\(children.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isHovered {
                        Button(action: { onAddChild(item.id) }) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                        .help("在此分组下新建会话")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
                )
                .onHover { isHovered = $0 }
                .contextMenu {
                    Button("⚡ 打开组内所有会话") { onOpenAllInGroup(item) }
                    Divider()
                    Button("➕ 在此分组下新建会话...") { onAddChild(item.id) }
                    Button("✏️ 重命名 / 编辑分组...") { onEdit(item) }
                    Divider()
                    Button("🗑️ 删除分组", role: .destructive) { sessionStore.deleteSession(id: item.id) }
                }
                
                if isExpanded, let children = item.children {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(children, id: \.id) { child in
                            SessionTreeNodeView(
                                item: child,
                                selectedSessionId: $selectedSessionId,
                                sessionStore: sessionStore,
                                onOpen: onOpen,
                                onOpenAllInGroup: onOpenAllInGroup,
                                onEdit: onEdit,
                                onAddChild: onAddChild
                            )
                        }
                    }
                    .padding(.leading, 14)
                }
            }
        } else {
            // Leaf Session Item
            let isSelected = (selectedSessionId == item.id)
            
            HStack(spacing: 8) {
                // Color Tag Dot
                if let hex = item.colorHex {
                    Circle()
                        .fill(Color(NSColor(hex: hex)))
                        .frame(width: 7, height: 7)
                }
                
                // Protocol Icon
                Image(systemName: item.iconName.isEmpty ? item.protocolType.iconName : item.iconName)
                    .font(.system(size: 13))
                    .foregroundColor(protocolColor(item.protocolType))
                    .frame(width: 16)
                
                // Details
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    
                    Text(subtitleText(for: item))
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? Color.white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isHovered && !isSelected {
                    Button(action: { onOpen(item) }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("连接会话")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.12) : Color.clear))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) {
                // Double-click to instantly open tab & connect
                selectedSessionId = item.id
                onOpen(item)
            }
            .onTapGesture(count: 1) {
                selectedSessionId = item.id
            }
            .contextMenu {
                Button("⚡ 打开并连接") { onOpen(item) }
                Divider()
                Button("✏️ 编辑会话...") { onEdit(item) }
                Button("📋 复制连接命令") {
                    NSPasteboard.general.clearContents()
                    if item.protocolType == .ssh {
                        let userPrefix = item.username.isEmpty ? "" : "\(item.username)@"
                        NSPasteboard.general.setString("ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o StrictHostKeyChecking=accept-new \(userPrefix)\(item.host) -p \(item.port)", forType: .string)
                    }
                }
                Divider()
                Button("🗑️ 删除会话", role: .destructive) { sessionStore.deleteSession(id: item.id) }
            }
        }
    }
    
    private func subtitleText(for item: SessionItem) -> String {
        switch item.protocolType {
        case .ssh, .telnet, .scp, .sftp, .ftp:
            return "\(item.username.isEmpty ? "" : item.username + "@")\(item.host):\(item.port)"
        case .serial:
            return "\(item.serialDevicePath ?? "/dev/cu.usbserial") (\(item.baudRate))"
        case .ble:
            return "BLE: \(item.bleDeviceName ?? "蓝牙设备")"
        case .local:
            return "本地 Shell (Zsh)"
        case .vnc:
            return "VNC: \(item.host):\(item.port)"
        }
    }
    
    private func protocolColor(_ proto: SessionProtocol) -> Color {
        switch proto {
        case .ssh: return .green
        case .sftp: return .teal
        case .scp: return .cyan
        case .telnet: return .orange
        case .serial: return .blue
        case .ble: return .indigo
        case .local: return .accentColor
        case .vnc: return .purple
        case .ftp: return .teal
        }
    }
}

// MARK: - New Group Dedicated Sheet
struct NewGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sessionStore: SessionStore
    
    @State private var groupName: String = "新建分组"
    @State private var selectedColor: String = "#F59E0B"
    
    private let presetColors = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#6B7280"]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("新建分组目录")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("分组名称")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                    
                    TextField("输入分组名称 (如：生产集群、网络交换机)", text: $groupName)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack(spacing: 12) {
                    Text("分组颜色")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)
                    
                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.self) { hex in
                            Circle()
                                .fill(Color(NSColor(hex: hex)))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColor == hex ? 2.5 : 0)
                                )
                                .onTapGesture { selectedColor = hex }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            
            Divider()
            
            HStack {
                Spacer()
                Button("创建分组") {
                    let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let newGroup = SessionItem(
                        name: trimmed.isEmpty ? "新建分组" : trimmed,
                        isGroup: true,
                        iconName: "folder.fill",
                        colorHex: selectedColor,
                        children: []
                    )
                    sessionStore.addSession(newGroup)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

