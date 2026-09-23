import AppKit

public final class HapticFeedbackHelper {
    public static let shared = HapticFeedbackHelper()
    
    private init() {}
    
    /// Trigger generic trackpad haptic feedback
    public func performGeneric() {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .generic,
                performanceTime: .now
            )
        }
    }
    
    /// Trigger alignment/guidance haptic feedback
    public func performAlignment() {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .now
            )
        }
    }
    
    /// Trigger level change haptic feedback (for dangerous commands or state shifts)
    public func performLevelChange() {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .levelChange,
                performanceTime: .now
            )
        }
    }
}
