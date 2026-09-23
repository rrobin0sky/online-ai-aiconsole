import SwiftUI
import QuickLook

public struct FTPBrowserView: View {
    let session: SessionItem
    @StateObject private var ftpService = FTPService()
    
    @State private var pathInput: String = "/"
    @State private var showingNewFolderDialog = false
    @State private var newFolderName = ""
    @State private var selectedFile: RemoteFileItem?
    @State private var filterQuery: String = ""
    @State private var previewFileItem: RemoteFileItem?
    @State private var previewFileContent: String?
    @State private var isPreviewSheetOpen: Bool = false
    
    public init(session: SessionItem) {
        self.session = session
    }
    
    private var breadcrumbSegments: [(name: String, fullPath: String)] {
        let parts = pathInput.split(separator: "/").map(String.init)
        var result: [(name: String, fullPath: String)] = [("/", "/")]
        var currentAcc = ""
        for part in parts {
            currentAcc += "/" + part
            result.append((part, currentAcc))
        }
        return result
    }
    
    private var displayedFiles: [RemoteFileItem] {
        if filterQuery.isEmpty {
            return ftpService.files
        }
        return ftpService.files.filter { $0.name.localizedCaseInsensitiveContains(filterQuery) }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Breadcrumb Bar & Action Bar
            HStack(spacing: 8) {
                Button(action: goUpDirectory) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(pathInput == "/" || pathInput.isEmpty)
                .help("返回上一级目录")
                
                // Breadcrumbs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(breadcrumbSegments, id: \.fullPath) { seg in
                            Button(action: {
                                enterDirectory(seg.fullPath)
                            }) {
                                HStack(spacing: 3) {
                                    if seg.fullPath == "/" {
                                        Image(systemName: "internaldrive")
                                            .font(.system(size: 10))
                                    }
                                    Text(seg.name)
                                        .font(.system(size: 11, weight: seg.fullPath == pathInput ? .bold : .regular))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(seg.fullPath == pathInput ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            
                            if seg.fullPath != breadcrumbSegments.last?.fullPath {
                                Text("/")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Search Filter
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("过滤文件...", text: $filterQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 110)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                
                Button(action: loadCurrentPath) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("刷新当前目录")
                
                Button(action: {
                    newFolderName = ""
                    showingNewFolderDialog = true
                }) {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Status Bar
            HStack(spacing: 8) {
                if ftpService.isConnecting {
                    ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                }
                Text(ftpService.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(ftpService.isLocal ? "本地根目录管理" : "SFTP 节点: \(session.host):\(session.port)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("• 空格键快速预览文件")
                    .font(.caption2)
                    .foregroundColor(.accentColor.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // File & Directory Table List
            if displayedFiles.isEmpty && !ftpService.isConnecting {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(filterQuery.isEmpty ? "当前目录为空" : "未找到匹配文件")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayedFiles, selection: $selectedFile) { file in
                    HStack(spacing: 10) {
                        Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(file.name))
                            .foregroundColor(file.isDirectory ? .yellow : fileColor(file.name))
                            .font(.system(size: 15))
                            .frame(width: 18)
                        
                        Text(file.name)
                            .font(.system(size: 12, weight: file.isDirectory ? .medium : .regular))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(file.permissions)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        if !file.isDirectory {
                            Text(formatSize(file.size))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        } else {
                            Text("--")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if file.isDirectory {
                            enterDirectory(file.path)
                        } else {
                            previewFile(file)
                        }
                    }
                    .contextMenu {
                        if !file.isDirectory {
                            Button("👀 快速预览 (Space)") { previewFile(file) }
                            Button("⬇️ 下载到「下载」文件夹") { ftpService.downloadFileToDownloads(item: file) }
                        }
                        Button("📋 复制完整路径") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(file.path, forType: .string)
                        }
                        Divider()
                        Button("🗑️ 删除项目", role: .destructive) { ftpService.deleteItem(item: file) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingNewFolderDialog) {
            VStack(spacing: 12) {
                Text("新建文件夹")
                    .font(.headline)
                
                TextField("输入文件夹名称", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("取消") { showingNewFolderDialog = false }
                    Spacer()
                    Button("创建") {
                        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            ftpService.createDirectory(named: trimmed)
                        }
                        showingNewFolderDialog = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 320)
        }
        .sheet(isPresented: $isPreviewSheetOpen) {
            VStack(spacing: 0) {
                HStack {
                    Label(previewFileItem?.name ?? "文件快速预览", systemImage: fileIcon(previewFileItem?.name ?? ""))
                        .font(.headline)
                    Spacer()
                    Button("关闭 (ESC)") { isPreviewSheetOpen = false }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                ScrollView {
                    Text(previewFileContent ?? "正在加载文件内容...")
                        .font(.system(size: 12, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))
            }
            .frame(width: 600, height: 450)
        }
        .task {
            let initialPath = (session.host == "localhost" || session.host == "127.0.0.1") ? NSHomeDirectory() : "/"
            pathInput = initialPath
            await ftpService.loadDirectory(for: session, directory: initialPath)
        }
    }
    
    private func enterDirectory(_ path: String) {
        pathInput = path
        Task {
            await ftpService.loadDirectory(for: session, directory: path)
        }
    }
    
    private func goUpDirectory() {
        let current = pathInput as NSString
        let parent = current.deletingLastPathComponent
        if !parent.isEmpty {
            enterDirectory(parent)
        }
    }
    
    private func loadCurrentPath() {
        let trimmed = pathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await ftpService.loadDirectory(for: session, directory: trimmed)
        }
    }
    
    private func previewFile(_ file: RemoteFileItem) {
        self.previewFileItem = file
        self.previewFileContent = "正在读取 \(file.name) 预览内容..."
        self.isPreviewSheetOpen = true
        
        if ftpService.isLocal {
            if let content = try? String(contentsOfFile: file.path, encoding: .utf8) {
                self.previewFileContent = content
            } else if let content = try? String(contentsOfFile: file.path, encoding: .ascii) {
                self.previewFileContent = content
            } else {
                self.previewFileContent = "二进制文件，无法以纯文本预览。"
            }
        } else {
            // Read remote head via ssh
            Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                var args = ["-p", "\(session.port)"]
                if let key = session.privateKeyPath, !key.isEmpty { args.append(contentsOf: ["-i", key]) }
                args.append(contentsOf: ["-o", "StrictHostKeyChecking=accept-new", "\(session.username)@\(session.host)", "head -n 200 '\(file.path)'"])
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                try? process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    self.previewFileContent = str
                } else {
                    self.previewFileContent = "无法读取远程文件预览内容或文件为空。"
                }
            }
        }
    }
    
    private func fileIcon(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".conf") || lower.hasSuffix(".cfg") || lower.hasSuffix(".ini") || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") {
            return "gearshape.2.fill"
        }
        if lower.hasSuffix(".log") || lower.hasSuffix(".txt") {
            return "doc.text.fill"
        }
        if lower.hasSuffix(".sh") || lower.hasSuffix(".py") || lower.hasSuffix(".swift") || lower.hasSuffix(".go") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if lower.hasSuffix(".tar") || lower.hasSuffix(".gz") || lower.hasSuffix(".zip") {
            return "doc.zipper"
        }
        return "doc.fill"
    }
    
    private func fileColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.hasSuffix(".sh") || lower.hasSuffix(".py") || lower.hasSuffix(".swift") {
            return .green
        }
        if lower.hasSuffix(".conf") || lower.hasSuffix(".json") || lower.hasSuffix(".yaml") {
            return .orange
        }
        if lower.hasSuffix(".log") {
            return .cyan
        }
        return .accentColor
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes)/1024.0) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes)/(1024.0*1024.0)) }
        return String(format: "%.1f GB", Double(bytes)/(1024.0*1024.0*1024.0))
    }
}
