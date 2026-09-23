import SwiftUI

public struct AICommandCardView: View {
    let card: AICommandCard
    let onExecute: (String) -> Void
    let onInsert: (String) -> Void
    
    @State private var executedStepIndices: Set<Int> = []
    @State private var isAllExecuted: Bool = false
    @State private var isCopied: Bool = false
    
    public init(card: AICommandCard, onExecute: @escaping (String) -> Void, onInsert: @escaping (String) -> Void) {
        self.card = card
        self.onExecute = onExecute
        self.onInsert = onInsert
    }
    
    private var commandLines: [String] {
        card.command
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Risk badge, explanation & Copy
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: card.riskLevel.iconName)
                        .font(.system(size: 11))
                    Text(riskTitle(card.riskLevel))
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(riskColor(card.riskLevel))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(riskColor(card.riskLevel).opacity(0.15))
                .cornerRadius(4)
                
                Text(card.explanation)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.command, forType: .string)
                    HapticFeedbackHelper.shared.performGeneric()
                    withAnimation { isCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { isCopied = false }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isCopied ? "已复制" : "复制")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(isCopied ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            
            // Stepper Command Pipeline (Discrete steps vs single block)
            if commandLines.count > 1 {
                VStack(spacing: 6) {
                    ForEach(Array(commandLines.enumerated()), id: \.offset) { idx, line in
                        let isStepDone = executedStepIndices.contains(idx)
                        let isComment = line.hasPrefix("#")
                        
                        if isComment {
                            HStack {
                                Text(line)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.top, 2)
                        } else {
                            HStack(spacing: 8) {
                                // Step Circle Badge
                                ZStack {
                                    Circle()
                                        .fill(isStepDone ? Color.green : Color.accentColor.opacity(0.2))
                                        .frame(width: 18, height: 18)
                                    if isStepDone {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Text("\(idx + 1)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                
                                Spacer()
                                
                                Button("执行此步") {
                                    executeStep(line: line, index: idx)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(isStepDone)
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.25))
                            .cornerRadius(6)
                        }
                    }
                }
            } else {
                // Single line command snippet container
                HStack {
                    Text(card.command)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }
            
            // Action Buttons Bar
            HStack(spacing: 8) {
                Button(action: {
                    onInsert(card.command)
                    HapticFeedbackHelper.shared.performGeneric()
                }) {
                    Label("填入终端 (不执行)", systemImage: "arrow.right.doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button(action: {
                    executeFullPipeline()
                }) {
                    Label(isAllExecuted ? "全部已执行" : "一键流水线执行", systemImage: isAllExecuted ? "checkmark.circle.fill" : "play.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(riskColor(card.riskLevel))
                .controlSize(.small)
                .disabled(isAllExecuted)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(riskColor(card.riskLevel).opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
    
    private func executeStep(line: String, index: Int) {
        if card.riskLevel == .dangerous {
            Task { @MainActor in
                let auth = await BiometricGuard.shared.authenticate(reason: "执行高危运维指令 (\(line.prefix(25))...)")
                if auth {
                    HapticFeedbackHelper.shared.performAlignment()
                    executedStepIndices.insert(index)
                    onExecute(line)
                } else {
                    HapticFeedbackHelper.shared.performLevelChange()
                }
            }
        } else {
            HapticFeedbackHelper.shared.performGeneric()
            executedStepIndices.insert(index)
            onExecute(line)
        }
    }
    
    private func executeFullPipeline() {
        if card.riskLevel == .dangerous {
            Task { @MainActor in
                let auth = await BiometricGuard.shared.authenticate(reason: "一键执行高危运维指令流水线")
                if auth {
                    HapticFeedbackHelper.shared.performAlignment()
                    isAllExecuted = true
                    for i in 0..<commandLines.count { executedStepIndices.insert(i) }
                    onExecute(card.command)
                } else {
                    HapticFeedbackHelper.shared.performLevelChange()
                }
            }
        } else {
            HapticFeedbackHelper.shared.performAlignment()
            isAllExecuted = true
            for i in 0..<commandLines.count { executedStepIndices.insert(i) }
            onExecute(card.command)
        }
    }
    
    private func riskTitle(_ risk: CommandRiskLevel) -> String {
        switch risk {
        case .safe: return "安全指令"
        case .caution: return "谨慎核对"
        case .dangerous: return "高危操作"
        }
    }
    
    private func riskColor(_ risk: CommandRiskLevel) -> Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
}
