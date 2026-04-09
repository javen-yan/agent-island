//
//  SessionState.swift
//  Agent Island
//
//  Unified state model for a Claude session.
//  Consolidates all state that was previously spread across multiple components.
//

import Foundation

/// Complete state for a single tracked agent session
/// This is the single source of truth - all state reads and writes go through SessionStore
struct SessionState: Equatable, Identifiable, Sendable {
    nonisolated private static let defaultPhaseSources = SessionPhaseSources()

    // MARK: - Identity

    let sessionId: String
    let agentType: AgentPlatform
    let cwd: String
    var transcriptPath: String?
    let projectName: String

    // MARK: - Instance Metadata

    var pid: Int?
    var tty: String?
    var isInTerminalMultiplexer: Bool
    var detectedTerminalBackend: TerminalBackend?

    // MARK: - State Machine

    /// Current phase in the session lifecycle
    var phase: SessionPhase
    var phaseSources: SessionPhaseSources

    // MARK: - Chat History

    /// All chat items for this session (replaces ChatHistoryManager.histories)
    var chatItems: [ChatHistoryItem]

    // MARK: - Tool Tracking

    /// Unified tool tracker (replaces 6+ dictionaries in ChatHistoryManager)
    var toolTracker: ToolTracker

    // MARK: - Subagent State

    /// State for Task tools and their nested subagent tools
    var subagentState: SubagentState

    // MARK: - Conversation Info (from JSONL parsing)

    var conversationInfo: ConversationInfo
    var lastUnifiedEvent: UnifiedAgentEvent?

    // MARK: - Clear Reconciliation

    /// When true, the next file update should reconcile chatItems with parser state
    /// This removes pre-/clear items that no longer exist in the JSONL
    var needsClearReconciliation: Bool

    // MARK: - Timestamps

    var lastActivity: Date
    var createdAt: Date

    // MARK: - Identifiable

    var id: String { sessionId }

    // MARK: - Initialization

    nonisolated init(
        sessionId: String,
        agentType: AgentPlatform = .claude,
        cwd: String,
        transcriptPath: String? = nil,
        projectName: String? = nil,
        pid: Int? = nil,
        tty: String? = nil,
        isInTerminalMultiplexer: Bool = false,
        detectedTerminalBackend: TerminalBackend? = nil,
        phase: SessionPhase = .idle,
        phaseSources: SessionPhaseSources? = nil,
        chatItems: [ChatHistoryItem] = [],
        toolTracker: ToolTracker? = nil,
        subagentState: SubagentState? = nil,
        conversationInfo: ConversationInfo? = nil,
        lastUnifiedEvent: UnifiedAgentEvent? = nil,
        needsClearReconciliation: Bool = false,
        lastActivity: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.agentType = agentType
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.projectName = projectName ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.pid = pid
        self.tty = tty
        self.isInTerminalMultiplexer = isInTerminalMultiplexer
        self.detectedTerminalBackend = detectedTerminalBackend
        self.phase = phase
        self.phaseSources = phaseSources ?? Self.defaultPhaseSources
        self.chatItems = chatItems
        self.toolTracker = toolTracker ?? ToolTracker()
        self.subagentState = subagentState ?? SubagentState()
        self.conversationInfo = conversationInfo ?? ConversationInfo(
            summary: nil, lastMessage: nil, lastMessageRole: nil,
            lastToolName: nil, firstUserMessage: nil, lastUserMessageDate: nil
        )
        self.lastUnifiedEvent = lastUnifiedEvent
        self.needsClearReconciliation = needsClearReconciliation
        self.lastActivity = lastActivity ?? Date()
        self.createdAt = createdAt ?? Date()
    }

    // MARK: - Derived Properties

    /// Whether this session needs user attention
    var needsAttention: Bool {
        phase.needsAttention
    }

    /// The active permission context, if any
    nonisolated var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase {
            return ctx
        }
        return nil
    }

    nonisolated var approvalMode: ApprovalMode? {
        phase.approvalMode
    }

    nonisolated var usesTerminalApproval: Bool {
        approvalMode == .terminal
    }

    nonisolated var providerCapabilities: ProviderCapabilities {
        ProviderCapabilities.baseline(for: agentType)
    }

    nonisolated var approvalCapability: ApprovalCapability {
        providerCapabilities.approvalCapability(approvalMode: approvalMode)
    }

    nonisolated var permissionSourceDescription: String {
        providerCapabilities.permissionSourceDescription(provider: agentType)
    }

    var unifiedViewKind: UnifiedAgentEvent.Kind {
        switch phase {
        case .waitingForApproval:
            return .permissionRequested
        case .processing:
            return .toolStarted
        case .compacting:
            return .sessionCompactionRequested
        case .waitingForInput, .idle:
            return .agentIdle
        case .ended:
            return .sessionEnded
        }
    }

    var unifiedStatusColor: String {
        switch unifiedViewKind {
        case .permissionRequested:
            return "approval"
        case .toolStarted, .sessionCompactionRequested:
            return "processing"
        case .agentIdle:
            return phase == .waitingForInput ? "ready" : "idle"
        case .sessionEnded:
            return "idle"
        default:
            return "idle"
        }
    }

    var unifiedPendingApprovalEvent: UnifiedAgentEvent? {
        guard let permission = activePermission else { return nil }

        return UnifiedAgentEvent(
            provider: agentType,
            sessionId: sessionId,
            kind: .permissionRequested,
            payload: .init(
                session: .init(
                    cwd: cwd,
                    transcriptPath: transcriptPath,
                    pid: pid,
                    tty: tty
                ),
                tool: .init(
                    callId: permission.toolUseId,
                    toolName: permission.toolName,
                    arguments: permission.formattedInput.map { ["display": $0] } ?? [:],
                    risk: nil
                ),
                permission: .init(
                    requestId: permission.toolUseId,
                    sourceKind: "tool_call",
                    providerEvent: nil
                ),
                metadata: [
                    "approvalMode": permission.mode.rawValue,
                    "permissionSource": permissionSourceDescription
                ]
            ),
            capabilityHints: .init(
                supportsAllow: providerCapabilities.toolControl.allow,
                supportsDeny: providerCapabilities.toolControl.deny,
                supportsAsk: providerCapabilities.supportsAskApproval,
                supportsArgumentPatch: providerCapabilities.toolControl.rewriteArgs,
                supportsAdditionalContext: providerCapabilities.sessionControl.injectStartContext,
                supportsStopTurn: providerCapabilities.sessionControl.stopTurn
            )
        )
    }

    // MARK: - UI Convenience Properties

    /// Stable identity for SwiftUI (combines PID and sessionId for animation stability)
    var stableId: String {
        if let pid = pid {
            return "\(pid)-\(sessionId)"
        }
        return sessionId
    }

    /// Display title: summary > first user message > project name
    var displayTitle: String {
        cleanedDisplayTitle(conversationInfo.summary)
            ?? cleanedDisplayTitle(conversationInfo.firstUserMessage)
            ?? projectName
    }

    /// Best hint for matching window title
    var windowHint: String {
        cleanedDisplayTitle(conversationInfo.summary) ?? projectName
    }

    /// Pending tool name if waiting for approval
    var pendingToolName: String? {
        activePermission?.toolName
    }

    /// Pending tool use ID
    var pendingToolId: String? {
        activePermission?.toolUseId
    }

    /// Formatted pending tool input for display
    var pendingToolInput: String? {
        activePermission?.formattedInput
    }

    /// Last message content
    var lastMessage: String? {
        conversationInfo.lastMessage
    }

    /// Last message role
    var lastMessageRole: String? {
        conversationInfo.lastMessageRole
    }

    /// Last tool name
    var lastToolName: String? {
        conversationInfo.lastToolName
    }

    /// Summary
    nonisolated var summary: String? {
        conversationInfo.summary
    }

    /// First user message
    nonisolated var firstUserMessage: String? {
        conversationInfo.firstUserMessage
    }

    /// Last user message date
    var lastUserMessageDate: Date? {
        conversationInfo.lastUserMessageDate
    }

    /// Whether the session can be interacted with
    var canInteract: Bool {
        phase.needsAttention
    }

    nonisolated var listState: SessionListState {
        SessionListState(
            sessionId: sessionId,
            agentType: agentType,
            cwd: cwd,
            transcriptPath: transcriptPath,
            projectName: projectName,
            pid: pid,
            tty: tty,
            isInTerminalMultiplexer: isInTerminalMultiplexer,
            detectedTerminalBackend: detectedTerminalBackend,
            phase: phase,
            conversationInfo: conversationInfo,
            lastActivity: lastActivity,
            createdAt: createdAt
        )
    }
}

func cleanedDisplayTitle(_ text: String?) -> String? {
    guard var text else { return nil }

    let patterns = [
        #"<environment_context>[\s\S]*?</environment_context>"#,
        #"<permissions instructions>[\s\S]*?</permissions instructions>"#,
        #"<app-context>[\s\S]*?</app-context>"#,
        #"<collaboration_mode>[\s\S]*?</collaboration_mode>"#,
        #"<skills_instructions>[\s\S]*?</skills_instructions>"#,
        #"<plugins_instructions>[\s\S]*?</plugins_instructions>"#
    ]

    for pattern in patterns {
        text = text.replacingOccurrences(
            of: pattern,
            with: " ",
            options: [.regularExpression]
        )
    }

    text = text
        .replacingOccurrences(of: #"\s+"#, with: " ", options: [.regularExpression])
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return text.isEmpty ? nil : text
}

// MARK: - Tool Tracker

/// Unified tool tracking - replaces multiple dictionaries in ChatHistoryManager
struct ToolTracker: Equatable, Sendable {
    /// Tools currently in progress, keyed by tool_use_id
    var inProgress: [String: ToolInProgress]

    /// All tool IDs we've seen (for deduplication)
    var seenIds: Set<String>

    /// Last JSONL file offset for incremental parsing
    var lastSyncOffset: UInt64

    /// Last sync timestamp
    var lastSyncTime: Date?

    nonisolated init(
        inProgress: [String: ToolInProgress] = [:],
        seenIds: Set<String> = [],
        lastSyncOffset: UInt64 = 0,
        lastSyncTime: Date? = nil
    ) {
        self.inProgress = inProgress
        self.seenIds = seenIds
        self.lastSyncOffset = lastSyncOffset
        self.lastSyncTime = lastSyncTime
    }

    /// Mark a tool ID as seen, returns true if it was new
    nonisolated mutating func markSeen(_ id: String) -> Bool {
        seenIds.insert(id).inserted
    }

    /// Check if a tool ID has been seen
    nonisolated func hasSeen(_ id: String) -> Bool {
        seenIds.contains(id)
    }

    /// Start tracking a tool
    nonisolated mutating func startTool(id: String, name: String) {
        guard markSeen(id) else { return }
        inProgress[id] = ToolInProgress(
            id: id,
            name: name,
            startTime: Date(),
            phase: .running
        )
    }

    /// Complete a tool
    nonisolated mutating func completeTool(id: String, success: Bool) {
        inProgress.removeValue(forKey: id)
    }
}

/// A tool currently in progress
struct ToolInProgress: Equatable, Sendable {
    let id: String
    let name: String
    let startTime: Date
    var phase: ToolInProgressPhase
}

/// Phase of a tool in progress
enum ToolInProgressPhase: Equatable, Sendable {
    case starting
    case running
    case pendingApproval
}

// MARK: - Subagent State

/// State for Task (subagent) tools
struct SubagentState: Equatable, Sendable {
    /// Active Task tools, keyed by task tool_use_id
    var activeTasks: [String: TaskContext]

    /// Ordered stack of active task IDs (most recent last) - used for proper tool assignment
    /// When multiple Tasks run in parallel, we use insertion order rather than timestamps
    var taskStack: [String]

    /// Mapping of agentId to Task description (for AgentOutputTool display)
    var agentDescriptions: [String: String]

    nonisolated init(activeTasks: [String: TaskContext] = [:], taskStack: [String] = [], agentDescriptions: [String: String] = [:]) {
        self.activeTasks = activeTasks
        self.taskStack = taskStack
        self.agentDescriptions = agentDescriptions
    }

    /// Whether there's an active subagent
    nonisolated var hasActiveSubagent: Bool {
        !activeTasks.isEmpty
    }

    /// Start tracking a Task tool
    nonisolated mutating func startTask(taskToolId: String, description: String? = nil) {
        activeTasks[taskToolId] = TaskContext(
            taskToolId: taskToolId,
            startTime: Date(),
            agentId: nil,
            description: description,
            subagentTools: []
        )
    }

    /// Stop tracking a Task tool
    nonisolated mutating func stopTask(taskToolId: String) {
        activeTasks.removeValue(forKey: taskToolId)
    }

    /// Set the agentId for a Task (called when agent file is discovered)
    nonisolated mutating func setAgentId(_ agentId: String, for taskToolId: String) {
        activeTasks[taskToolId]?.agentId = agentId
        if let description = activeTasks[taskToolId]?.description {
            agentDescriptions[agentId] = description
        }
    }

    /// Add a subagent tool to a specific Task by ID
    nonisolated mutating func addSubagentToolToTask(_ tool: SubagentToolCall, taskId: String) {
        activeTasks[taskId]?.subagentTools.append(tool)
    }

    /// Set all subagent tools for a specific Task (used when updating from agent file)
    nonisolated mutating func setSubagentTools(_ tools: [SubagentToolCall], for taskId: String) {
        activeTasks[taskId]?.subagentTools = tools
    }

    /// Add a subagent tool to the most recent active Task
    nonisolated mutating func addSubagentTool(_ tool: SubagentToolCall) {
        // Find most recent active task (for parallel Task support)
        guard let mostRecentTaskId = activeTasks.keys.max(by: {
            (activeTasks[$0]?.startTime ?? .distantPast) < (activeTasks[$1]?.startTime ?? .distantPast)
        }) else { return }

        activeTasks[mostRecentTaskId]?.subagentTools.append(tool)
    }

    /// Update the status of a subagent tool across all active Tasks
    nonisolated mutating func updateSubagentToolStatus(toolId: String, status: ToolStatus) {
        for taskId in activeTasks.keys {
            if let index = activeTasks[taskId]?.subagentTools.firstIndex(where: { $0.id == toolId }) {
                activeTasks[taskId]?.subagentTools[index].status = status
                return
            }
        }
    }
}

/// Context for an active Task tool
struct TaskContext: Equatable, Sendable {
    let taskToolId: String
    let startTime: Date
    var agentId: String?
    var description: String?
    var subagentTools: [SubagentToolCall]
}
