import Foundation

struct AgentInteractionRegistry {
    static let shared = AgentInteractionRegistry()

    func supportsConversationHistory(for agentType: AgentPlatform) -> Bool {
        switch agentType {
        case .claude, .codex:
            return true
        case .gemini:
            return false
        }
    }
}
