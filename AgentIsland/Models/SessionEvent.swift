//
//  SessionEvent.swift
//  Agent Island
//
//  Unified event types for the session state machine.
//  All state changes flow through SessionStore.process(event).
//

import Foundation

/// All events that can affect session state
/// This is the single entry point for state mutations
enum SessionEvent: Sendable {
    /// A unified agent event was received from the translation layer
    case unifiedEventReceived(UnifiedAgentEvent)

    // MARK: - Permission Events (user actions)

    /// User approved a permission request
    case permissionApproved(sessionId: String, toolUseId: String)

    /// User denied a permission request
    case permissionDenied(sessionId: String, toolUseId: String, reason: String?)

    /// Permission socket failed (connection died before response)
    case permissionSocketFailed(sessionId: String, toolUseId: String)

    // MARK: - File Events (from ConversationParser)

    /// JSONL file was updated with new content
    case fileUpdated(FileUpdatePayload)

    // MARK: - Tool Completion Events (from JSONL parsing)

    /// A tool was detected as completed via JSONL result
    /// This is the authoritative signal that a tool has finished
    case toolCompleted(sessionId: String, toolUseId: String, result: ToolCompletionResult)

    // MARK: - Interrupt Events (from JSONLInterruptWatcher)

    /// User interrupted Claude (detected via JSONL)
    case interruptDetected(sessionId: String)

    // MARK: - Subagent Events (Task tool tracking)

    /// A Task (subagent) tool has started
    case subagentStarted(sessionId: String, taskToolId: String)

    /// A tool was executed within an active subagent
    case subagentToolExecuted(sessionId: String, tool: SubagentToolCall)

    /// A subagent tool completed (status update)
    case subagentToolCompleted(sessionId: String, toolId: String, status: ToolStatus)

    /// A Task (subagent) tool has stopped
    case subagentStopped(sessionId: String, taskToolId: String)

    /// Agent file was updated with new subagent tools (from AgentFileWatcher)
    case agentFileUpdated(sessionId: String, taskToolId: String, tools: [SubagentToolInfo])

    // MARK: - Clear Events (from JSONL detection)

    /// User issued /clear command - reset UI state while keeping session alive
    case clearDetected(sessionId: String)

    // MARK: - Session Lifecycle

    /// Session has ended
    case sessionEnded(sessionId: String)

    /// Request to load initial history from file
    case loadHistory(sessionId: String, cwd: String)

    /// History load completed
    case historyLoaded(sessionId: String, messages: [ChatMessage], completedTools: Set<String>, toolResults: [String: SessionToolResult], structuredResults: [String: ToolResultData], conversationInfo: ConversationInfo, phaseHint: SessionPhase?)
}

/// Payload for file update events
struct FileUpdatePayload: Sendable {
    let sessionId: String
    let cwd: String
    /// Messages to process - either only new messages (if isIncremental) or all messages
    let messages: [ChatMessage]
    /// When true, messages contains only NEW messages since last update
    /// When false, messages contains ALL messages (used for initial load or after /clear)
    let isIncremental: Bool
    let completedToolIds: Set<String>
    let toolResults: [String: SessionToolResult]
    let structuredResults: [String: ToolResultData]
    let conversationInfo: ConversationInfo
    let phaseHint: SessionPhase?
}

/// Result of a tool completion detected from JSONL
struct ToolCompletionResult: Sendable {
    let status: ToolStatus
    let result: String?
    let structuredResult: ToolResultData?

    nonisolated static func from(parserResult: SessionToolResult?, structuredResult: ToolResultData?) -> ToolCompletionResult {
        let status: ToolStatus
        if parserResult?.isInterrupted == true {
            status = .interrupted
        } else if parserResult?.isError == true {
            status = .error
        } else {
            status = .success
        }

        var resultText: String? = nil
        if let r = parserResult {
            if !r.isInterrupted {
                if let stdout = r.stdout, !stdout.isEmpty {
                    resultText = stdout
                } else if let stderr = r.stderr, !stderr.isEmpty {
                    resultText = stderr
                } else if let content = r.content, !content.isEmpty {
                    resultText = content
                }
            }
        }

        return ToolCompletionResult(status: status, result: resultText, structuredResult: structuredResult)
    }
}

// MARK: - Hook Event Extensions

extension HookEvent {
    nonisolated var approvalRequestType: HookEvent.ApprovalRequestType {
        if permissionModeValue == .terminal || status == HookEvent.Status.terminalApprovalRequired.rawValue {
            return .terminal
        }
        if permissionModeValue == .nativeApp || status == HookEvent.Status.waitingForApproval.rawValue {
            return .app
        }
        return .none
    }

    nonisolated var resolvedApprovalMode: ApprovalMode? {
        switch approvalRequestType {
        case .terminal:
            return .terminal
        case .app:
            return .nativeApp
        case .none:
            return nil
        }
    }

    nonisolated var shouldAwaitPermissionResponse: Bool {
        switch approvalRequestType {
        case .none:
            return false
        case .app, .terminal:
            return true
        }
    }

    nonisolated var statusValue: HookEvent.Status {
        HookEvent.Status(rawValue: status) ?? .unknown
    }

    nonisolated var internalEventValue: HookEvent.InternalEventName {
        HookEvent.InternalEventName(rawValue: internalEvent ?? "") ?? .unknown
    }

    nonisolated var permissionModeValue: HookEvent.PermissionMode? {
        guard let permissionMode else { return nil }
        return HookEvent.PermissionMode(rawValue: permissionMode)
    }

    nonisolated var usesLegacyEventFallback: Bool {
        internalEventValue == .unknown
    }

    nonisolated var isSessionEndLike: Bool {
        switch internalEventValue {
        case .sessionEnded:
            return true
        case .unknown:
            return event == HookEvent.EventName.sessionEnd.rawValue
        default:
            return false
        }
    }

    nonisolated var isStopLike: Bool {
        switch internalEventValue {
        case .stopped:
            return true
        case .unknown:
            return event == HookEvent.EventName.stop.rawValue
        default:
            return false
        }
    }

    nonisolated var isPreToolLike: Bool {
        switch internalEventValue {
        case .toolWillRun, .permissionRequested:
            return true
        case .unknown:
            return event == HookEvent.EventName.beforeTool.rawValue
                || event == HookEvent.EventName.preToolUse.rawValue
                || event == HookEvent.EventName.permissionRequest.rawValue
        default:
            return false
        }
    }

    nonisolated var isPostToolLike: Bool {
        switch internalEventValue {
        case .toolDidRun:
            return true
        case .unknown:
            return event == HookEvent.EventName.afterTool.rawValue
                || event == HookEvent.EventName.postToolUse.rawValue
        default:
            return false
        }
    }

    nonisolated var isSubagentStopLike: Bool {
        switch internalEventValue {
        case .subagentStopped:
            return true
        case .unknown:
            return event == HookEvent.EventName.subagentStop.rawValue
        default:
            return false
        }
    }

    nonisolated var protocolDebugSummary: String {
        let internalName = internalEvent ?? "nil"
        let officialName = event.isEmpty ? "nil" : event
        let permission = permissionMode ?? "nil"
        return "internal=\(internalName) official=\(officialName) permission=\(permission)"
    }

    /// Whether this event should trigger a file sync
    nonisolated var shouldSyncFile: Bool {
        guard AgentInteractionRegistry.shared.supportsConversationHistory(for: agentType) else {
            return false
        }

        switch unifiedEvent.kind {
        case .turnInputSubmitted, .toolStarted, .toolCompleted, .turnCompleted:
            return true
        default:
            return false
        }
    }
}

// MARK: - Debug Description

extension SessionEvent: CustomStringConvertible {
    nonisolated var description: String {
        switch self {
        case .unifiedEventReceived(let event):
            return "unifiedEventReceived(\(event.provider.rawValue):\(event.kind.rawValue), session: \(event.sessionId.prefix(8)))"
        case .permissionApproved(let sessionId, let toolUseId):
            return "permissionApproved(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)))"
        case .permissionDenied(let sessionId, let toolUseId, _):
            return "permissionDenied(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)))"
        case .permissionSocketFailed(let sessionId, let toolUseId):
            return "permissionSocketFailed(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)))"
        case .fileUpdated(let payload):
            return "fileUpdated(session: \(payload.sessionId.prefix(8)), messages: \(payload.messages.count))"
        case .interruptDetected(let sessionId):
            return "interruptDetected(session: \(sessionId.prefix(8)))"
        case .clearDetected(let sessionId):
            return "clearDetected(session: \(sessionId.prefix(8)))"
        case .sessionEnded(let sessionId):
            return "sessionEnded(session: \(sessionId.prefix(8)))"
        case .loadHistory(let sessionId, _):
            return "loadHistory(session: \(sessionId.prefix(8)))"
        case .historyLoaded(let sessionId, let messages, _, _, _, _, _):
            return "historyLoaded(session: \(sessionId.prefix(8)), messages: \(messages.count))"
        case .toolCompleted(let sessionId, let toolUseId, let result):
            return "toolCompleted(session: \(sessionId.prefix(8)), tool: \(toolUseId.prefix(12)), status: \(result.status))"
        case .subagentStarted(let sessionId, let taskToolId):
            return "subagentStarted(session: \(sessionId.prefix(8)), task: \(taskToolId.prefix(12)))"
        case .subagentToolExecuted(let sessionId, let tool):
            return "subagentToolExecuted(session: \(sessionId.prefix(8)), tool: \(tool.name))"
        case .subagentToolCompleted(let sessionId, let toolId, let status):
            return "subagentToolCompleted(session: \(sessionId.prefix(8)), tool: \(toolId.prefix(12)), status: \(status))"
        case .subagentStopped(let sessionId, let taskToolId):
            return "subagentStopped(session: \(sessionId.prefix(8)), task: \(taskToolId.prefix(12)))"
        case .agentFileUpdated(let sessionId, let taskToolId, let tools):
            return "agentFileUpdated(session: \(sessionId.prefix(8)), task: \(taskToolId.prefix(12)), tools: \(tools.count))"
        }
    }
}
