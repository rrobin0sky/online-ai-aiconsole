import SwiftUI

public struct SnippetManagerView: View {
    @ObservedObject var snippetStore: SnippetStore = SnippetStore.shared
    let onExecuteCommand: (String) -> Void
    let onInsertCommand: (String) -> Void
    
    @State private var selectedCategory: String = "全部"
    @State private var searchQuery: String = ""
    @State private var showingAddSheet: Bool = false
    @State private var editingSnippet: SnippetItem?
    
    public init(onExecuteCommand: @escaping (String) -> Void, onInsertCommand: @escaping (String) -> Void) {
        self.onExecuteCommand = onExecuteCommand
        self.onInsertCommand = onInsertCommand
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search, Action & Category Segment (Standard 32pt/Pro Header)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                        TextField("搜索常用运维命令或别名...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(5)
                    
                    Button(action: {
                        HapticFeedbackHelper.shared.performGeneric()
                        editingSnippet = nil
                        showingAddSheet = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                            Text("新建")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("新建常用命令模板 (⌘N)")
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(snippetStore.allCategories, id: \.self) { cat in
                            let isSelected = (selectedCategory == cat)
                            Button(action: {
                                HapticFeedbackHelper.shared.performGeneric()
                                selectedCategory = cat
                            }) {
                                Text(cat)
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                            .shadow(color: isSelected ? Color.black.opacity(0.06) : Color.clear, radius: 1, y: 1)
                                    )
                                    .foregroundColor(isSelected ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Snippets List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSnippets) { snippet in
                        SnippetCardRow(
                            snippet: snippet,
                            onExecute: { onExecuteCommand(snippet.command) },
                            onInsert: { onInsertCommand(snippet.command) },
                            onEdit: {
                                editingSnippet = snippet
                                showingAddSheet = true
                            },
                            onDelete: { snippetStore.deleteSnippet(id: snippet.id) }
                        )
                    }
                }
                .padding(10)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            SnippetEditSheet(snippetStore: snippetStore, editingSnippet: editingSnippet)
        }
    }
    
    private var filteredSnippets: [SnippetItem] {
        var list = snippetStore.snippets
        if selectedCategory != "全部" {
            list = list.filter { $0.category == selectedCategory }
        }
        if !searchQuery.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.command.localizedCaseInsensitiveContains(searchQuery) ||
                $0.category.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        return list
    }
}

struct SnippetCardRow: View {
    let snippet: SnippetItem
    let onExecute: () -> Void
    let onInsert: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isInserted: Bool = false
    @State private var isExecuted: Bool = false
    @State private var isHovered: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snippet.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(snippet.category)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .cornerRadius(3)
            }
            
            Text(snippet.command)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.25))
                .cornerRadius(4)
            
            HStack(spacing: 6) {
                Button(action: {
                    HapticFeedbackHelper.shared.performGeneric()
                    onInsert()
                    withAnimation { isInserted = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { isInserted = false }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isInserted ? "checkmark" : "arrow.right.doc.on.clipboard")
                            .font(.system(size: 8))
                        Text(isInserted ? "已填入" : "填入")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(isInserted ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("将命令文本填入当前活动终端")
                
                Button(action: {
                    HapticFeedbackHelper.shared.performGeneric()
                    onExecute()
                    withAnimation { isExecuted = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { isExecuted = false }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isExecuted ? "checkmark" : "play.fill")
                            .font(.system(size: 8))
                        Text(isExecuted ? "已执行" : "执行")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(isExecuted ? Color.green : Color.accentColor)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("立即发送并在终端执行此命令 (Return)")
                
                Spacer()
                
                if isHovered {
                    Button(action: {
                        HapticFeedbackHelper.shared.performGeneric()
                        onEdit()
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("编辑命令片段")
                    
                    Button(action: {
                        HapticFeedbackHelper.shared.performAlignment()
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 18, height: 18)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("删除命令片段")
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.04))
        )
        .onHover { isHovered = $0 }
    }
}

struct SnippetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var snippetStore: SnippetStore
    
    @State private var title: String
    @State private var command: String
    @State private var category: String
    
    private let editingSnippet: SnippetItem?
    
    init(snippetStore: SnippetStore, editingSnippet: SnippetItem? = nil) {
        self.snippetStore = snippetStore
        self.editingSnippet = editingSnippet
        _title = State(initialValue: editingSnippet?.title ?? "")
        _command = State(initialValue: editingSnippet?.command ?? "")
        _category = State(initialValue: editingSnippet?.category ?? "常用运维")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editingSnippet == nil ? "新建常用命令片段" : "编辑命令片段")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
            }
            .padding()
            
            Divider()
            
            Form {
                TextField("标题 / 功能描述", text: $title)
                TextField("分类 (如: Docker / 系统监控 / 数据库)", text: $category)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shell 命令内容:")
                        .font(.caption)
                    TextEditor(text: $command)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 120)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                }
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            HStack {
                Spacer()
                Button("保存片段") {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedTitle.isEmpty && !trimmedCmd.isEmpty else { return }
                    
                    if let editing = editingSnippet {
                        var updated = editing
                        updated.title = trimmedTitle
                        updated.command = trimmedCmd
                        updated.category = category.isEmpty ? "常用运维" : category
                        snippetStore.updateSnippet(updated)
                    } else {
                        let newSnippet = SnippetItem(
                            title: trimmedTitle,
                            command: trimmedCmd,
                            category: category.isEmpty ? "常用运维" : category
                        )
                        snippetStore.addSnippet(newSnippet)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || command.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 420)
    }
}
