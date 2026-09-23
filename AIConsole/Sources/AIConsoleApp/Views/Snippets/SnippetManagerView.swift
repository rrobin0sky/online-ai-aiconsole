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
            // Search, Action & Category Segment
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        TextField("搜索命令或标题...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    
                    Button(action: {
                        editingSnippet = nil
                        showingAddSheet = true
                    }) {
                        Label("新建", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(snippetStore.allCategories, id: \.self) { cat in
                            Button(action: { selectedCategory = cat }) {
                                Text(cat)
                                    .font(.caption)
                                    .fontWeight(selectedCategory == cat ? .semibold : .regular)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedCategory == cat ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                    .foregroundColor(selectedCategory == cat ? .white : .primary)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
            
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snippet.title)
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
                
                Text(snippet.category)
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            }
            
            Text(snippet.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.3))
                .cornerRadius(4)
            
            HStack(spacing: 8) {
                Button(action: {
                    onInsert()
                    withAnimation { isInserted = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { isInserted = false }
                    }
                }) {
                    Label(isInserted ? "已填入" : "填入", systemImage: isInserted ? "checkmark" : "arrow.right.doc.on.clipboard")
                        .font(.caption2)
                        .foregroundColor(isInserted ? .green : .primary)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button(action: {
                    onExecute()
                    withAnimation { isExecuted = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { isExecuted = false }
                    }
                }) {
                    Label(isExecuted ? "已执行" : "一键执行", systemImage: isExecuted ? "checkmark" : "play.fill")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(isExecuted ? .green : .accentColor)
                .controlSize(.mini)
                
                Spacer()
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("编辑片段")
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("删除片段")
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
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
