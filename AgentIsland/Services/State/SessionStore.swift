//
//  SessionStore.swift
//  Agent Island
//
//  Central state manager for all agent sessions.
//  Single source of truth - all state mutations flow through process().
//

import Combine
import Foundation
import Mixpanel
import os.log

/// Central state manager for all tracked agent sessions
/// Uses Swift actor for thread-safe state mutations
actor SessionStore {
    static let shared = SessionStore()

    /// Logger for session store (nonisolated static for cross-context access)
    nonisolated static let logger = Logger(subsystem: "com.agentisland", category: "Session")

    // MARK: - State

    /// All sessions keyed by sessionId
    private var sessions: [String: SessionState] = [:]

    /// Pending file syncs (debounced)
    private var pendingSyncs: [String: Task<Void, Never>] = [:]

    /// Sessions currently loading transcript metadata in the background.
    private var pendingConversationHydrations = Set<String>()

    /// Sync debounce interval (100ms)
    private let syncDebounceNs: UInt64 = 100_000_000

    /// Default number of recent chat items to retain in memory per session.
    /// Older stable items are trimmed to keep long-running sessions bounded.
    private var chatHistoryRetentionLimit: Int {
        AppSettings.chatHistoryRetentionLimitSnapshot()
    }

    // MARK: - Published State (for UI)

    /// Publisher for session state changes (nonisolated for Combine subscription from any context)
    private nonisolated(unsafe) let sessionsSubject = CurrentValueSubject<[SessionState], Never>([])
    private nonisolated(unsafe) let sessionSummariesSubject = CurrentValueSubject<[SessionListState], Never>([])

    /// Public publisher for UI subscription
    nonisolated var sessionsPublisher: AnyPublisher<[SessionState], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    nonisolated var sessionSummariesPublisher: AnyPublisher<[SessionListState], Never> {
        sessionSummariesSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Event Processing

    /// Process any session event - the ONLY way to mutate state
    func process(_ event: SessionEvent) async {
        Self.logger.debug("Processing: \(String(describing: event), privacy: .public)")
        AppDiagnosticsLogger.log(.debug, category: .session, "Processing event=\(String(describing: event))")

        switch event {
        case .unifiedEventReceived(let unifiedEvent):
            await processUnifiedEvent(unifiedEvent)

        case .permissionApproved(let sessionId, let toolUseId):
            await processPermissionApproved(sessionId: sessionId, toolUseId: toolUseId)

        case .permissionDenied(let sessionId, let toolUseId, let reason):
            await processPermissionDenied(sessionId: sessionId, toolUseId: toolUseId, reason: reason)

        case .permissionSocketFailed(let sessionId, let toolUseId):
            await processSocketFailure(sessionId: sessionId, toolUseId: toolUseId)

        case .fileUpdated(let payload):
            await processFileUpdate(payload)

        case .interruptDetected(let sessionId):
            await processInterrupt(sessionId: sessionId)

        case .clearDetected(let sessionId):
            await processClearDetected(sessionId: sessionId)

        case .sessionEnded(let sessionId):
            AppDiagnosticsLogger.log(.info, category: .session, "Session ended signal session=\(sessionId)")
            await processSessionEnd(sessionId: sessionId)

        case .loadHistory(let sessionId, let cwd):
            await loadHistoryFromFile(sessionId: sessionId, cwd: cwd)

        case .historyLoaded(let sessionId, let messages, let completedTools, let toolResults, let structuredResults, let conversationInfo, let phaseHint):
            AppDiagnosticsLogger.log(.debug, category: .session, "History loaded session=\(sessionId) messages=\(messages.count)")
            await processHistoryLoaded(
                sessionId: sessionId,
                messages: messages,
                completedTools: completedTools,
                toolResults: toolResults,
                structuredResults: structuredResults,
                conversationInfo: conversationInfo,
                phaseHint: phaseHint
            )

        case .toolCompleted(let sessionId, let toolUseId, let result):
            await processToolCompleted(sessionId: sessionId, toolUseId: toolUseId, result: result)

        // MARK: - Subagent Events

        case .subagentStarted(let sessionId, let taskToolId):
            processSubagentStarted(sessionId: sessionId, taskToolId: taskToolId)

        case .subagentToolExecuted(let sessionId, let tool):
            processSubagentToolExecuted(sessionId: sessionId, tool: tool)

        case .subagentToolCompleted(let sessionId, let toolId, let status):
            processSubagentToolCompleted(sessionId: sessionId, toolId: toolId, status: status)

        case .subagentStopped(let sessionId, let taskToolId):
            processSubagentStopped(sessionId: sessionId, taskToolId: taskToolId)

        case .agentFileUpdated:
            // No longer used - subagent tools are populated from JSONL completion
            break
        }

        await MainActor.run {
            AgentEventBus.shared.publishDomain(.sessionEventProcessed(event))
        }
        publishState()
    }

    // MARK: - Hook Event Processing

    private func processUnifiedEvent(_ event: UnifiedAgentEvent) async {
        let sessionId = event.sessionId
        let isNewSession = sessions.index(forKey: sessionId) == nil
        var session = sessions[sessionId] ?? createSession(from: event)

        if isNewSession {
            Mixpanel.mainInstance().track(event: "Session Started")
            AppDiagnosticsLogger.log(.info, category: .session, "Session started session=\(sessionId) provider=\(event.provider.rawValue)")
        }

        session.lastUnifiedEvent = event
        session.lastActivity = event.timestamp

        if let sessionContext = event.payload.session {
            let existingTree = ProcessTreeBuilder.shared.buildTree()

            if let transcriptPath = sessionContext.transcriptPath, !transcriptPath.isEmpty {
                session.transcriptPath = transcriptPath
            }
            if let pid = sessionContext.pid {
                session.pid = pid
                session.detectedTerminalBackend = TerminalMultiplexerRegistry.shared.detectedBackend(
                    pid: pid,
                    tree: existingTree
                )
            }
            if let tty = sessionContext.tty, !tty.isEmpty {
                session.tty = tty.replacingOccurrences(of: "/dev/", with: "")
            }

            if let resolvedBackend = await TerminalMultiplexerRegistry.shared.resolvedBackend(
                pid: session.pid,
                tty: session.tty,
                preferred: TerminalMultiplexerRegistry.fallbackBackend,
                tree: existingTree
            ) {
                session.detectedTerminalBackend = resolvedBackend
                session.isInTerminalMultiplexer = true
            } else {
                session.isInTerminalMultiplexer = false
            }
        }

        applyUnifiedConversationInfo(event: event, session: &session)
        ToolEventProcessor.processUnifiedToolEvent(event: event, session: &session)
        ToolEventProcessor.processUnifiedSubagentEvent(event: event, session: &session)

        if event.kind == .sessionEnded {
            session.phaseSources.set(nil, for: .transcript)
            applyPhaseUpdate(to: &session, source: .runtime, phase: .ended)

            if await shouldRetainEndedSession(session) {
                AppDiagnosticsLogger.log(.info, category: .session, "Retaining ended session=\(sessionId)")
                session.phaseSources.set(nil, for: .runtime)
                applyPhaseUpdate(
                    to: &session,
                    source: .runtime,
                    phase: AgentInteractionRegistry.shared.canSendMessages(for: session) ? .waitingForInput : .idle
                )
                sessions[sessionId] = session
            } else {
                AppDiagnosticsLogger.log(.info, category: .session, "Removing ended session=\(sessionId)")
                sessions.removeValue(forKey: sessionId)
                cancelPendingSync(sessionId: sessionId)
            }
            return
        }

        if event.shouldResetSubagentState {
            session.subagentState = SubagentState()
        }

        if let mappedPhase = mappedPhase(for: event, currentPhase: session.phase) {
            if case .ended = mappedPhase {
                session.phaseSources.set(nil, for: .transcript)
            }
            applyPhaseUpdate(to: &session, source: .runtime, phase: mappedPhase)
        }

        sessions[sessionId] = session

        if let cwd = event.payload.session?.cwd,
           shouldHydrateConversationInfo(for: session, isNewSession: isNewSession) {
            scheduleConversationHydration(sessionId: sessionId, cwd: cwd)
        }

        let syncCwd = event.payload.session?.cwd ?? (session.cwd.isEmpty ? nil : session.cwd)
        if event.shouldSyncTranscript, let cwd = syncCwd {
            scheduleFileSync(sessionId: sessionId, cwd: cwd)
        }
    }

    private func createSession(from event: UnifiedAgentEvent) -> SessionState {
        let cwd = event.payload.session?.cwd ?? ""
        let phase = mappedPhase(for: event, currentPhase: .idle) ?? .idle

        return SessionState(
            sessionId: event.sessionId,
            agentType: event.provider,
            cwd: cwd,
            transcriptPath: event.payload.session?.transcriptPath,
            projectName: cwd.isEmpty ? event.provider.rawValue.capitalized : URL(fileURLWithPath: cwd).lastPathComponent,
            pid: event.payload.session?.pid,
            tty: event.payload.session?.tty?.replacingOccurrences(of: "/dev/", with: ""),
            isInTerminalMultiplexer: false,
            phase: phase,
            phaseSources: SessionPhaseSources(transcript: nil, runtime: phase),
            lastUnifiedEvent: event,
            lastActivity: event.timestamp,
            createdAt: event.timestamp
        )
    }

    private func mappedPhase(for event: UnifiedAgentEvent, currentPhase: SessionPhase) -> SessionPhase? {
        event.mappedSessionPhase(currentPhase: currentPhase)
    }

    private func applyUnifiedConversationInfo(event: UnifiedAgentEvent, session: inout SessionState) {
        let trimmedMessage = event.payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let message = trimmedMessage, !message.isEmpty else { return }

        var info = session.conversationInfo

        switch event.kind {
        case .turnInputSubmitted:
            if info.firstUserMessage == nil {
                info = ConversationInfo(
                    summary: info.summary,
                    lastMessage: message,
                    lastMessageRole: "user",
                    lastToolName: info.lastToolName,
                    firstUserMessage: message,
                    lastUserMessageDate: event.timestamp
                )
            } else {
                info = ConversationInfo(
                    summary: info.summary,
                    lastMessage: message,
                    lastMessageRole: "user",
                    lastToolName: info.lastToolName,
                    firstUserMessage: info.firstUserMessage,
                    lastUserMessageDate: event.timestamp
                )
            }
        case .notification, .agentIdle, .turnCompleted:
            info = ConversationInfo(
                summary: info.summary,
                lastMessage: message,
                lastMessageRole: "assistant",
                lastToolName: info.lastToolName,
                firstUserMessage: info.firstUserMessage,
                lastUserMessageDate: info.lastUserMessageDate
            )
        default:
            return
        }

        session.conversationInfo = info
    }

    private func shouldRetainEndedSession(_ session: SessionState) async -> Bool {
        if session.isInTerminalMultiplexer, let tty = session.tty {
            let backend: TerminalBackend
            if let detected = session.detectedTerminalBackend {
                backend = detected
            } else {
                backend = await TerminalMultiplexerRegistry.shared.resolvedBackend(
                    pid: session.pid,
                    tty: tty,
                    preferred: TerminalMultiplexerRegistry.fallbackBackend
                ) ?? TerminalMultiplexerRegistry.fallbackBackend
            }
            let adapter = await TerminalMultiplexerRegistry.shared.adapter(for: backend)
            if await adapter.hasTarget(forTTY: tty) {
                return true
            }
        }

        guard let tty = session.tty else {
            return false
        }

        let tree = ProcessTreeBuilder.shared.buildTree()
        return ProcessTreeBuilder.shared.hasProcesses(onTTY: tty, tree: tree)
    }

    // MARK: - Subagent Event Handlers

    /// Handle subagent started event
    private func processSubagentStarted(sessionId: String, taskToolId: String) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.startTask(taskToolId: taskToolId)
        applyPhaseUpdate(to: &session, source: .runtime, phase: .processing)
        sessions[sessionId] = session
    }

    /// Handle subagent tool executed event
    private func processSubagentToolExecuted(sessionId: String, tool: SubagentToolCall) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.addSubagentTool(tool)
        applyPhaseUpdate(to: &session, source: .runtime, phase: .processing)
        sessions[sessionId] = session
    }

    /// Handle subagent tool completed event
    private func processSubagentToolCompleted(sessionId: String, toolId: String, status: ToolStatus) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.updateSubagentToolStatus(toolId: toolId, status: status)
        let hasWaitingApprovalPhase: Bool
        if case .waitingForApproval = session.phase {
            hasWaitingApprovalPhase = true
        } else {
            hasWaitingApprovalPhase = false
        }
        if !session.subagentState.hasActiveSubagent && !hasWaitingApprovalPhase {
            applyPhaseUpdate(to: &session, source: .runtime, phase: .waitingForInput)
        }
        sessions[sessionId] = session
    }

    /// Handle subagent stopped event
    private func processSubagentStopped(sessionId: String, taskToolId: String) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.stopTask(taskToolId: taskToolId)
        let hasWaitingApprovalPhase: Bool
        if case .waitingForApproval = session.phase {
            hasWaitingApprovalPhase = true
        } else {
            hasWaitingApprovalPhase = false
        }
        if !session.subagentState.hasActiveSubagent && !hasWaitingApprovalPhase {
            applyPhaseUpdate(to: &session, source: .runtime, phase: .waitingForInput)
        }
        sessions[sessionId] = session
        // Subagent tools will be populated from agent file in processFileUpdated
    }

    /// Parse ISO8601 timestamp string
    private func parseTimestamp(_ timestampStr: String?) -> Date? {
        guard let str = timestampStr else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str)
    }

    private func anyCodableInput(from input: [String: String]) -> [String: AnyCodable]? {
        guard !input.isEmpty else { return nil }
        var result: [String: AnyCodable] = [:]
        for (key, value) in input {
            result[key] = AnyCodable(value)
        }
        return result
    }

    // MARK: - Permission Processing

    private func processPermissionApproved(sessionId: String, toolUseId: String) async {
        guard var session = sessions[sessionId] else { return }

        // Update tool status in chat history first
        ToolEventProcessor.updateToolStatus(in: &session, toolId: toolUseId, status: .running)

        // Check if there are other tools still waiting for approval
        if let nextPending = ToolEventProcessor.findNextPendingTool(in: session, excluding: toolUseId) {
            // Another tool is waiting - stay in waitingForApproval with that tool's context
            let newPhase = SessionPhase.waitingForApproval(PermissionContext(
                toolUseId: nextPending.id,
                toolName: nextPending.name,
                toolInput: anyCodableInput(from: nextPending.input),
                mode: nextPending.mode,
                receivedAt: nextPending.timestamp
            ))
            applyPhaseUpdate(to: &session, source: .runtime, phase: newPhase)
            Self.logger.debug("Switched to next pending tool: \(nextPending.id.prefix(12), privacy: .public)")
        } else {
            // No more pending tools - transition to processing
            if case .waitingForApproval(let ctx) = session.phase, ctx.toolUseId == toolUseId {
                applyPhaseUpdate(to: &session, source: .runtime, phase: .processing)
            } else if case .waitingForApproval = session.phase {
                // The approved tool wasn't the one in phase context, but no others pending
                // This can happen if tools were approved out of order
                applyPhaseUpdate(to: &session, source: .runtime, phase: .processing)
            }
        }

        sessions[sessionId] = session
    }

    // MARK: - Tool Completion Processing

    /// Process a tool completion event (from JSONL detection)
    /// This is the authoritative handler for tool completions - ensures consistent state updates
    private func processToolCompleted(sessionId: String, toolUseId: String, result: ToolCompletionResult) async {
        guard var session = sessions[sessionId] else { return }

        // Check if this tool is already completed (avoid duplicate processing)
        if let existingItem = session.chatItems.first(where: { $0.id == toolUseId }),
           case .toolCall(let tool) = existingItem.type,
           tool.status == .success || tool.status == .error || tool.status == .interrupted {
            // Already completed, skip
            return
        }

        // Update the tool status
        ToolEventProcessor.processToolCompleted(session: &session, toolUseId: toolUseId, result: result)

        // Update session phase if needed
        // If the completed tool was the one in the phase context, switch to next pending or processing
        if case .waitingForApproval(let ctx) = session.phase, ctx.toolUseId == toolUseId {
            if let nextPending = ToolEventProcessor.findNextPendingTool(in: session, excluding: toolUseId) {
                let newPhase = SessionPhase.waitingForApproval(PermissionContext(
                    toolUseId: nextPending.id,
                    toolName: nextPending.name,
                    toolInput: anyCodableInput(from: nextPending.input),
                    mode: nextPending.mode,
                    receivedAt: nextPending.timestamp
                ))
                applyPhaseUpdate(to: &session, source: .runtime, phase: newPhase)
                Self.logger.debug("Switched to next pending tool after completion: \(nextPending.id.prefix(12), privacy: .public)")
            } else {
                applyPhaseUpdate(to: &session, source: .runtime, phase: .processing)
            }
        }

        applyChatHistoryRetention(to: &session)
        sessions[sessionId] = session
    }

    private func processPermissionDenied(sessionId: String, toolUseId: String, reason: String?) async {
        guard var session = sessions[sessionId] else { return }

        // Update tool status in chat history first
        ToolEventProcessor.updateToolStatus(in: &session, toolId: toolUseId, status: .error)

        // Check if there are other tools still waiting for approval
        if let nextPending = ToolEventProcessor.findNextPendingTool(in: session, excluding: toolUseId) {
            // Another tool is waiting - stay in waitingForApproval with that tool's context
            let newPhase = SessionPhase.waitingForApproval(PermissionContext(
                toolUseId: nextPending.id,
                toolName: nextPending.name,
                toolInput: anyCodableInput(from: nextPending.input),
                mode: nextPending.mode,
                receivedAt: nextPending.timestamp
            ))
            applyPhaseUpdate(to: &session, source: .runtime, phase: newPhase)
            Self.logger.debug("Switched to next pending tool after denial: \(nextPending.id.prefix(12), privacy: .public)")
        } else {
            // No more pending tools - transition to processing (Claude will handle denial)
            if case .waitingForApproval(let ctx) = session.phase, ctx.toolUseId == toolUseId {
                applyPhaseUpdate(to: &session, source: .runtime, phase: .processing)
            } else if case .waitingForApproval = session.phase {
                // The denied tool wasn't the one in phase context, but no others pending
                applyPhaseUpdate(to: &session, source: .runtime, phase: .processing)
            }
        }

        sessions[sessionId] = session
    }

    private func processSocketFailure(sessionId: String, toolUseId: String) async {
        guard var session = sessions[sessionId] else { return }

        // Mark the failed tool's status as error
        ToolEventProcessor.updateToolStatus(in: &session, toolId: toolUseId, status: .error)

        // Check if there are other tools still waiting for approval
        if let nextPending = ToolEventProcessor.findNextPendingTool(in: session, excluding: toolUseId) {
            // Another tool is waiting - switch to that tool's context
            let newPhase = SessionPhase.waitingForApproval(PermissionContext(
                toolUseId: nextPending.id,
                toolName: nextPending.name,
                toolInput: anyCodableInput(from: nextPending.input),
                mode: nextPending.mode,
                receivedAt: nextPending.timestamp
            ))
            applyPhaseUpdate(to: &session, source: .runtime, phase: newPhase)
            Self.logger.debug("Switched to next pending tool after socket failure: \(nextPending.id.prefix(12), privacy: .public)")
        } else {
            // No more pending tools - clear permission state
            if case .waitingForApproval(let ctx) = session.phase, ctx.toolUseId == toolUseId {
                applyPhaseUpdate(to: &session, source: .runtime, phase: .idle)
            } else if case .waitingForApproval = session.phase {
                // The failed tool wasn't in phase context, but no others pending
                applyPhaseUpdate(to: &session, source: .runtime, phase: .idle)
            }
        }

        sessions[sessionId] = session
    }

    // MARK: - File Update Processing

    private func processFileUpdate(_ payload: FileUpdatePayload) async {
        guard var session = sessions[payload.sessionId] else { return }

        // Update conversationInfo from JSONL (summary, lastMessage, etc.)
        session.conversationInfo = payload.conversationInfo
        if let phaseHint = payload.phaseHint,
           !shouldPreserveWaitingForApproval(
                currentPhase: session.phase,
                nextPhase: phaseHint,
                completedToolIds: payload.completedToolIds
           ) {
            applyPhaseUpdate(to: &session, source: .transcript, phase: phaseHint)
        }

        // Handle /clear reconciliation - remove items that no longer exist in parser state
        if session.needsClearReconciliation {
            // Build set of valid IDs from the payload messages
            var validIds = Set<String>()
            for message in payload.messages {
                for (blockIndex, block) in message.content.enumerated() {
                    switch block {
                    case .toolUse(let tool):
                        validIds.insert(tool.id)
                    case .text, .thinking, .interrupted:
                        let itemId = "\(message.id)-\(block.typePrefix)-\(blockIndex)"
                        validIds.insert(itemId)
                    }
                }
            }

            // Filter chatItems to only keep valid items OR items that are very recent
            // (within last 2 seconds - these are hook-created placeholders for post-clear tools)
            let cutoffTime = Date().addingTimeInterval(-2)
            let previousCount = session.chatItems.count
            session.chatItems = session.chatItems.filter { item in
                validIds.contains(item.id) || item.timestamp > cutoffTime
            }

            // Also reset tool tracker
            session.toolTracker = ToolTracker()
            session.subagentState = SubagentState()

            session.needsClearReconciliation = false
            Self.logger.debug("Clear reconciliation: kept \(session.chatItems.count) of \(previousCount) items")
        }

        if payload.isIncremental {
            let existingIds = Set(session.chatItems.map { $0.id })

            for message in payload.messages {
                for (blockIndex, block) in message.content.enumerated() {
                    if case .toolUse(let tool) = block {
                        if let idx = session.chatItems.firstIndex(where: { $0.id == tool.id }) {
                            if case .toolCall(let existingTool) = session.chatItems[idx].type {
                                session.chatItems[idx] = ChatHistoryItem(
                                    id: tool.id,
                                    type: .toolCall(ToolCallItem(
                                        agentType: session.agentType,
                                        name: tool.name,
                                        input: tool.input,
                                        detailLocator: existingTool.detailLocator ?? ToolCallItem.DetailLocator(
                                            sessionId: session.sessionId,
                                            cwd: session.cwd,
                                            toolUseId: tool.id
                                        ),
                                        status: existingTool.status,
                                        approvalMode: existingTool.approvalMode,
                                        result: existingTool.result,
                                        structuredResult: existingTool.structuredResult,
                                        subagentTools: existingTool.subagentTools
                                    )),
                                    timestamp: message.timestamp
                                )
                            }
                            continue
                        }
                    }

                    let item = createChatItem(
                        sessionId: session.sessionId,
                        cwd: session.cwd,
                        agentType: session.agentType,
                        from: block,
                        message: message,
                        blockIndex: blockIndex,
                        existingIds: existingIds,
                        completedTools: payload.completedToolIds,
                        toolResults: payload.toolResults,
                        structuredResults: payload.structuredResults,
                        toolTracker: &session.toolTracker
                    )

                    if let item = item {
                        session.chatItems.append(item)
                    }
                }
            }
        } else {
            let existingIds = Set(session.chatItems.map { $0.id })

            for message in payload.messages {
                for (blockIndex, block) in message.content.enumerated() {
                    if case .toolUse(let tool) = block {
                        if let idx = session.chatItems.firstIndex(where: { $0.id == tool.id }) {
                            if case .toolCall(let existingTool) = session.chatItems[idx].type {
                                session.chatItems[idx] = ChatHistoryItem(
                                    id: tool.id,
                                    type: .toolCall(ToolCallItem(
                                        agentType: session.agentType,
                                        name: tool.name,
                                        input: tool.input,
                                        detailLocator: existingTool.detailLocator ?? ToolCallItem.DetailLocator(
                                            sessionId: session.sessionId,
                                            cwd: session.cwd,
                                            toolUseId: tool.id
                                        ),
                                        status: existingTool.status,
                                        approvalMode: existingTool.approvalMode,
                                        result: existingTool.result,
                                        structuredResult: existingTool.structuredResult,
                                        subagentTools: existingTool.subagentTools
                                    )),
                                    timestamp: message.timestamp
                                )
                            }
                            continue
                        }
                    }

                    let item = createChatItem(
                        sessionId: session.sessionId,
                        cwd: session.cwd,
                        agentType: session.agentType,
                        from: block,
                        message: message,
                        blockIndex: blockIndex,
                        existingIds: existingIds,
                        completedTools: payload.completedToolIds,
                        toolResults: payload.toolResults,
                        structuredResults: payload.structuredResults,
                        toolTracker: &session.toolTracker
                    )

                    if let item = item {
                        session.chatItems.append(item)
                    }
                }
            }

            session.chatItems.sort { $0.timestamp < $1.timestamp }
        }

        session.toolTracker.lastSyncTime = Date()

        await populateSubagentToolsFromAgentFiles(
            session: &session,
            cwd: payload.cwd,
            structuredResults: payload.structuredResults
        )

        applyChatHistoryRetention(to: &session)
        sessions[payload.sessionId] = session

        await emitToolCompletionEvents(
            sessionId: payload.sessionId,
            session: session,
            completedToolIds: payload.completedToolIds,
            toolResults: payload.toolResults,
            structuredResults: payload.structuredResults
        )
    }

    /// Populate subagent tools for Task tools using their agent JSONL files
    private func populateSubagentToolsFromAgentFiles(
        session: inout SessionState,
        cwd: String,
        structuredResults: [String: ToolResultData]
    ) async {
        for i in 0..<session.chatItems.count {
            guard case .toolCall(var tool) = session.chatItems[i].type,
                  tool.name == "Task",
                  let structuredResult = structuredResults[session.chatItems[i].id],
                  case .task(let taskResult) = structuredResult,
                  !taskResult.agentId.isEmpty else { continue }

            let taskToolId = session.chatItems[i].id

            // Store agentId → description mapping for AgentOutputTool display
            if let description = session.subagentState.activeTasks[taskToolId]?.description {
                session.subagentState.agentDescriptions[taskResult.agentId] = description
            } else if let description = tool.input["description"] {
                session.subagentState.agentDescriptions[taskResult.agentId] = description
            }

            guard let provider = SessionTranscriptProviderRegistry.shared.provider(for: session.agentType) else {
                continue
            }

            let subagentToolInfos = await provider.parseSubagentTools(
                agentId: taskResult.agentId,
                cwd: cwd
            )

            guard !subagentToolInfos.isEmpty else { continue }

            tool.subagentTools = subagentToolInfos.map { info in
                SubagentToolCall(
                    id: info.id,
                    name: info.name,
                    input: info.input,
                    status: info.isCompleted ? .success : .running,
                    timestamp: parseTimestamp(info.timestamp) ?? Date()
                )
            }

            session.chatItems[i] = ChatHistoryItem(
                id: taskToolId,
                type: .toolCall(tool),
                timestamp: session.chatItems[i].timestamp
            )

            Self.logger.debug("Populated \(subagentToolInfos.count) subagent tools for Task \(taskToolId.prefix(12), privacy: .public) from agent \(taskResult.agentId.prefix(8), privacy: .public)")
        }
    }

    /// Emit toolCompleted events for tools that have results in JSONL but aren't marked complete yet
    private func emitToolCompletionEvents(
        sessionId: String,
        session: SessionState,
        completedToolIds: Set<String>,
        toolResults: [String: SessionToolResult],
        structuredResults: [String: ToolResultData]
    ) async {
        for item in session.chatItems {
            guard case .toolCall(let tool) = item.type else { continue }

            // Only emit for tools that are running or waiting but have results in JSONL
            guard tool.status == .running || tool.status == .waitingForApproval else { continue }
            guard completedToolIds.contains(item.id) else { continue }

            let result = ToolCompletionResult.from(
                parserResult: toolResults[item.id],
                structuredResult: structuredResults[item.id]
            )

            // Process the completion event (this will update state and phase consistently)
            await process(.toolCompleted(sessionId: sessionId, toolUseId: item.id, result: result))
        }
    }

    /// Create chat item (checks existingIds to avoid duplicates)
    private func createChatItem(
        sessionId: String,
        cwd: String,
        agentType: AgentPlatform,
        from block: MessageBlock,
        message: ChatMessage,
        blockIndex: Int,
        existingIds: Set<String>,
        completedTools: Set<String>,
        toolResults: [String: SessionToolResult],
        structuredResults: [String: ToolResultData],
        toolTracker: inout ToolTracker
    ) -> ChatHistoryItem? {
        switch block {
        case .text(let text):
            let itemId = "\(message.id)-text-\(blockIndex)"
            guard !existingIds.contains(itemId) else { return nil }

            if message.role == .user {
                return ChatHistoryItem(id: itemId, type: .user(text), timestamp: message.timestamp)
            } else {
                return ChatHistoryItem(id: itemId, type: .assistant(text), timestamp: message.timestamp)
            }

        case .toolUse(let tool):
            guard toolTracker.markSeen(tool.id) else { return nil }

            let isCompleted = completedTools.contains(tool.id)
            let status: ToolStatus = isCompleted ? .success : .running

            // Extract result text for completed tools
            var resultText: String? = nil
            if isCompleted, let parserResult = toolResults[tool.id] {
                if let stdout = parserResult.stdout, !stdout.isEmpty {
                    resultText = stdout
                } else if let stderr = parserResult.stderr, !stderr.isEmpty {
                    resultText = stderr
                } else if let content = parserResult.content, !content.isEmpty {
                    resultText = content
                }
            }

            return ChatHistoryItem(
                id: tool.id,
                type: .toolCall(ToolCallItem(
                    agentType: agentType,
                    name: tool.name,
                    input: tool.input,
                    detailLocator: ToolCallItem.DetailLocator(
                        sessionId: sessionId,
                        cwd: cwd,
                        toolUseId: tool.id
                    ),
                    status: status,
                    approvalMode: nil,
                    result: resultText,
                    structuredResult: structuredResults[tool.id],
                    subagentTools: []
                )),
                timestamp: message.timestamp
            )

        case .thinking(let text):
            let itemId = "\(message.id)-thinking-\(blockIndex)"
            guard !existingIds.contains(itemId) else { return nil }
            return ChatHistoryItem(id: itemId, type: .thinking(text), timestamp: message.timestamp)

        case .interrupted:
            let itemId = "\(message.id)-interrupted-\(blockIndex)"
            guard !existingIds.contains(itemId) else { return nil }
            return ChatHistoryItem(id: itemId, type: .interrupted, timestamp: message.timestamp)
        }
    }

    // MARK: - Interrupt Processing

    private func processInterrupt(sessionId: String) async {
        guard var session = sessions[sessionId] else { return }

        // Clear subagent state
        session.subagentState = SubagentState()

        // Mark running tools as interrupted
        ToolEventProcessor.markRunningToolsInterrupted(session: &session)

        // Codex/Claude can leave a stale hook/transcript processing phase behind after Esc.
        // Clear active phase sources first so runtime idle can win immediately.
        session.phaseSources.set(nil, for: .transcript)

        // Transition out of processing immediately. If we can still message the agent,
        // treat interrupt as returning to ready-for-input rather than fully idle.
        let nextPhase: SessionPhase = AgentInteractionRegistry.shared.canSendMessages(for: session)
            ? .waitingForInput
            : .idle
        applyPhaseUpdate(to: &session, source: .runtime, phase: nextPhase)

        sessions[sessionId] = session

        // Codex writes interrupt markers into its transcript without emitting a hook event,
        // so pull one incremental sync to surface the interrupted message in chat history.
        scheduleFileSync(sessionId: sessionId, cwd: session.cwd)
    }

    // MARK: - Clear Processing

    private func processClearDetected(sessionId: String) async {
        guard var session = sessions[sessionId] else { return }

        Self.logger.info("Processing /clear for session \(sessionId.prefix(8), privacy: .public)")

        // Mark that a clear happened - the next fileUpdated will reconcile
        // by removing items that no longer exist in the parser's state
        session.needsClearReconciliation = true
        sessions[sessionId] = session

        Self.logger.info("/clear processed for session \(sessionId.prefix(8), privacy: .public) - marked for reconciliation")
    }

    // MARK: - Session End Processing

    private func processSessionEnd(sessionId: String) async {
        sessions.removeValue(forKey: sessionId)
        cancelPendingSync(sessionId: sessionId)
        pendingConversationHydrations.remove(sessionId)
    }

    // MARK: - History Loading

    private func loadHistoryFromFile(sessionId: String, cwd: String) async {
        pendingConversationHydrations.remove(sessionId)

        guard let session = sessions[sessionId],
              let provider = SessionTranscriptProviderRegistry.shared.provider(for: session.agentType),
              let snapshot = await provider.loadHistory(for: session) else {
            return
        }

        // Process loaded history
        await process(.historyLoaded(
            sessionId: sessionId,
            messages: snapshot.messages,
            completedTools: snapshot.completedToolIds,
            toolResults: snapshot.toolResults,
            structuredResults: snapshot.structuredResults,
            conversationInfo: snapshot.conversationInfo,
            phaseHint: snapshot.phaseHint
        ))
    }

    private func processHistoryLoaded(
        sessionId: String,
        messages: [ChatMessage],
        completedTools: Set<String>,
        toolResults: [String: SessionToolResult],
        structuredResults: [String: ToolResultData],
        conversationInfo: ConversationInfo,
        phaseHint: SessionPhase?
    ) async {
        guard var session = sessions[sessionId] else { return }

        // Update conversationInfo (summary, lastMessage, etc.)
        session.conversationInfo = conversationInfo
        if let phaseHint,
           !shouldPreserveWaitingForApproval(
                currentPhase: session.phase,
                nextPhase: phaseHint,
                completedToolIds: completedTools
           ) {
            applyPhaseUpdate(to: &session, source: .transcript, phase: phaseHint)
        }

        // Convert messages to chat items
        let existingIds = Set(session.chatItems.map { $0.id })

        for message in messages {
            for (blockIndex, block) in message.content.enumerated() {
                let item = createChatItem(
                    sessionId: session.sessionId,
                    cwd: session.cwd,
                    agentType: session.agentType,
                    from: block,
                    message: message,
                    blockIndex: blockIndex,
                    existingIds: existingIds,
                    completedTools: completedTools,
                    toolResults: toolResults,
                    structuredResults: structuredResults,
                    toolTracker: &session.toolTracker
                )

                if let item = item {
                    session.chatItems.append(item)
                }
            }
        }

        // Sort by timestamp
        session.chatItems.sort { $0.timestamp < $1.timestamp }

        applyChatHistoryRetention(to: &session)
        sessions[sessionId] = session
    }

    private func applyChatHistoryRetention(to session: inout SessionState) {
        let limit = chatHistoryRetentionLimit
        guard session.chatItems.count > limit else { return }

        let protectedIds = Set(session.chatItems.compactMap { item -> String? in
            guard case .toolCall(let tool) = item.type else { return nil }
            switch tool.status {
            case .running, .waitingForApproval:
                return item.id
            case .success, .error, .interrupted:
                return nil
            }
        })

        let trailingIds = Set(session.chatItems.suffix(limit).map(\.id))
        let retainedIds = trailingIds.union(protectedIds)
        guard retainedIds.count < session.chatItems.count else { return }

        session.chatItems = session.chatItems.filter { retainedIds.contains($0.id) }
        pruneToolTracking(for: &session, retainedToolIds: retainedIds)
    }

    private func pruneToolTracking(for session: inout SessionState, retainedToolIds: Set<String>) {
        session.toolTracker.seenIds = session.toolTracker.seenIds.filter {
            retainedToolIds.contains($0) || session.toolTracker.inProgress[$0] != nil
        }
        session.toolTracker.inProgress = session.toolTracker.inProgress.filter {
            retainedToolIds.contains($0.key)
        }
    }

    // MARK: - File Sync Scheduling

    private func scheduleFileSync(sessionId: String, cwd: String) {
        // Cancel existing sync
        cancelPendingSync(sessionId: sessionId)

        // Schedule new debounced sync
        pendingSyncs[sessionId] = Task { [weak self, syncDebounceNs] in
            try? await Task.sleep(nanoseconds: syncDebounceNs)
            guard !Task.isCancelled else { return }

            guard let self,
                  let session = await self.session(for: sessionId),
                  let provider = SessionTranscriptProviderRegistry.shared.provider(for: session.agentType),
                  let result = await provider.syncIncremental(for: session) else {
                return
            }

            if result.clearDetected {
                await self.process(.clearDetected(sessionId: sessionId))
            }

            guard !result.newMessages.isEmpty || result.clearDetected || result.phaseHint != nil else {
                return
            }

            let payload = FileUpdatePayload(
                sessionId: sessionId,
                cwd: cwd,
                messages: result.newMessages,
                isIncremental: !result.clearDetected,
                completedToolIds: result.completedToolIds,
                toolResults: result.toolResults,
                structuredResults: result.structuredResults,
                conversationInfo: result.conversationInfo,
                phaseHint: result.phaseHint
            )

            await DefaultCapabilityDispatcher.shared.handle(.fileSyncReceived(payload))
        }
    }

    private func shouldPreserveWaitingForApproval(
        currentPhase: SessionPhase,
        nextPhase: SessionPhase,
        completedToolIds: Set<String>
    ) -> Bool {
        guard case .waitingForApproval(let context) = currentPhase else {
            return false
        }

        if completedToolIds.contains(context.toolUseId) {
            return false
        }

        return nextPhase == .processing
    }

    private func shouldHydrateConversationInfo(for session: SessionState, isNewSession: Bool) -> Bool {
        guard SessionTranscriptProviderRegistry.shared.supportsHistory(for: session.agentType) else {
            return false
        }

        if pendingConversationHydrations.contains(session.sessionId) {
            return false
        }

        if !(session.summary?.isEmpty == false || session.firstUserMessage?.isEmpty == false) {
            return true
        }

        // New sessions can arrive with only transient hook state; allow one early hydration
        // so the instances list gets a stable title without requiring the chat view to open.
        return isNewSession && session.chatItems.isEmpty
    }

    private func scheduleConversationHydration(sessionId: String, cwd: String) {
        guard !pendingConversationHydrations.contains(sessionId) else { return }
        pendingConversationHydrations.insert(sessionId)

        Task {
            await DefaultCapabilityDispatcher.shared.handle(.historyLoadRequested(sessionId: sessionId, cwd: cwd))
        }
    }

    private func cancelPendingSync(sessionId: String) {
        pendingSyncs[sessionId]?.cancel()
        pendingSyncs.removeValue(forKey: sessionId)
    }

    private func applyPhaseUpdate(
        to session: inout SessionState,
        source: SessionPhaseSource,
        phase: SessionPhase?
    ) {
        let currentPhase = session.phase
        session.phaseSources.set(phase, for: source)
        let resolved = session.phaseSources.resolved(fallback: currentPhase)
        guard resolved != currentPhase else { return }

        if currentPhase.canTransition(to: resolved) {
            session.phase = resolved
        } else {
            Self.logger.debug(
                "Invalid phase merge transition: \(String(describing: currentPhase), privacy: .public) -> \(String(describing: resolved), privacy: .public), source: \(String(describing: source), privacy: .public)"
            )
        }
    }

    // MARK: - State Publishing

    private func publishState() {
        let sortedSessions = Array(sessions.values).sorted { $0.projectName < $1.projectName }
        let sortedSummaries = sortedSessions.map { $0.listState }
        sessionsSubject.send(sortedSessions)
        sessionSummariesSubject.send(sortedSummaries)
        Task { @MainActor in
            AgentEventBus.shared.publishDomain(.sessionsUpdated(sortedSummaries))
        }
    }

    // MARK: - Queries

    /// Get a specific session
    func session(for sessionId: String) -> SessionState? {
        sessions[sessionId]
    }

    /// Check if there's an active permission for a session
    func hasActivePermission(sessionId: String) -> Bool {
        guard let session = sessions[sessionId] else { return false }
        if case .waitingForApproval = session.phase {
            return true
        }
        return false
    }

    /// Get all current sessions
    func allSessions() -> [SessionState] {
        Array(sessions.values)
    }

    func applyChatHistoryRetentionToAllSessions() {
        var mutated = false
        for sessionId in sessions.keys {
            guard var session = sessions[sessionId] else { continue }
            let originalCount = session.chatItems.count
            applyChatHistoryRetention(to: &session)
            if session.chatItems.count != originalCount {
                sessions[sessionId] = session
                mutated = true
            }
        }

        if mutated {
            publishState()
        }
    }
}
