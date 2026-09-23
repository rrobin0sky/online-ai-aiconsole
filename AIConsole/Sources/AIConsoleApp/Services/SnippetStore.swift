import Foundation
import Combine

@MainActor
public final class SnippetStore: ObservableObject {
    public static let shared = SnippetStore()
    
    @Published public var snippets: [SnippetItem] = []
    
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AIConsole", isDirectory: true)
        self.fileURL = appDir.appendingPathComponent("snippets.json")
        
        load()
        if snippets.isEmpty {
            loadDefaultPresets()
        }
    }
    
    public func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([SnippetItem].self, from: data) else { return }
        self.snippets = list
    }
    
    public func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: fileURL)
    }
    
    public func addSnippet(_ snippet: SnippetItem) {
        snippets.insert(snippet, at: 0)
        save()
    }
    
    public func updateSnippet(_ snippet: SnippetItem) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
            save()
        }
    }
    
    public func deleteSnippet(id: UUID) {
        snippets.removeAll(where: { $0.id == id })
        save()
    }
    
    public var allCategories: [String] {
        let categories = Set(snippets.map { $0.category })
        return ["全部"] + Array(categories).sorted()
    }
    
    private func loadDefaultPresets() {
        self.snippets = [
            // 系统与性能
            SnippetItem(title: "系统资源概览 (CPU/内存/磁盘)", command: "echo '=== CPU & 内存 ===' && free -h && echo '=== 磁盘使用 ===' && df -h && echo '=== 系统负载 ===' && uptime", category: "系统监控"),
            SnippetItem(title: "查看实时占用最高的前10个进程", command: "ps aux --sort=-%mem | head -n 11", category: "系统监控"),
            SnippetItem(title: "查看系统当前登录用户与终端", command: "w", category: "系统监控"),
            
            // 网络与端口
            SnippetItem(title: "查看所有监听端口及对应进程", command: "netstat -tulnp || ss -tulnp", category: "网络排查"),
            SnippetItem(title: "测试远程主机端口连通性", command: "nc -zv 127.0.0.1 80", category: "网络排查"),
            SnippetItem(title: "查看网络流量与连接概况", command: "ss -s", category: "网络排查"),
            
            // Docker 运维
            SnippetItem(title: "查看正在运行的容器 (带资源占用)", command: "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' && docker stats --no-stream", category: "Docker"),
            SnippetItem(title: "实时跟踪指定容器最新日志", command: "docker logs -f --tail 100 <container_name>", category: "Docker"),
            SnippetItem(title: "清理所有已停止容器与无用镜像", command: "docker system prune -f", category: "Docker"),
            
            // 日志与排错
            SnippetItem(title: "实时跟踪 Nginx 访问与错误日志", command: "tail -f /var/log/nginx/access.log /var/log/nginx/error.log", category: "日志排错"),
            SnippetItem(title: "查看 Systemd 服务最近错误日志", command: "journalctl -xe --no-pager -n 50", category: "日志排错"),
            SnippetItem(title: "快速查找大文件 (大于 100MB)", command: "find / -type f -size +100M -exec ls -lh {} + 2>/dev/null | awk '{ print $5, $9 }' | sort -hr | head -n 15", category: "日志排错"),
            
            // 常用服务管理
            SnippetItem(title: "重启 Nginx 并检查配置文件", command: "nginx -t && systemctl reload nginx", category: "服务管理"),
            SnippetItem(title: "查看防火墙开放规则 (UFW / iptables)", command: "ufw status verbose || iptables -L -n -v", category: "服务管理")
        ]
        save()
    }
}
