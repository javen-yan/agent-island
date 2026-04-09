//
//  ToolEventProcessor.swift
//  Agent Island
//
//  Handles tool and subagent event processing logic.
//  Extracted from SessionStore to reduce complexity.
//

import Foundation
import os.log

nonisolated private let toolEventLogger = Logger(subsystem: "com.agentisland", category: "ToolEvents")

/// Processes tool-related events and updates session state
enum ToolEventProcessor {
    // MARK: - Tool Tracking

    nonisolated static func processUnifiedToolEvent(
        event: UnifiedAgentEvent,
        session: inout SessionState
    ) {
        guard let tool = event.payload.tool,
              let toolUseId = tool.callId else { return }

        if session.subagentState.hasActiveSubagent && tool.toolName != "Task" {
            return
        }

        switch event.kind {
        case .permissionRequested, .toolStarted:
            session.toolTracker.startTool(id: toolUseId, name: tool.toolName)

            let toolExists = session.chatItems.contains { $0.id == toolUseId }
            if !toolExists {
                let shouldAwaitPermission = event.kind == .permissionRequested
                let initialStatus: ToolStatus = shouldAwaitPermission ? .waitingForApproval : .running
                let placeholderItem = ChatHistoryItem(
                    id: toolUseId,
                    type: .toolCall(ToolCallItem(
                        agentType: session.agentType,
                        name: tool.toolName,
                        input: extractToolInput(from: tool.arguments),
                        status: initialStatus,
                        approvalMode: shouldAwaitPermission ? event.approvalMode : nil,
                        result: nil,
                        structuredResult: nil,
                        subagentTools: []
                    )),
                    timestamp: event.timestamp
                )
                session.chatItems.append(placeholderItem)
                toolEventLogger.debug("Created unified placeholder tool entry for \(toolUseId.prefix(16), privacy: .public)")
            }

        case .toolCompleted:
            session.toolTracker.completeTool(id: toolUseId, success: true)
            updateToolStatus(in: &session, toolId: toolUseId, status: .success)

        case .toolFailed:
            session.toolTracker.completeTool(id: toolUseId, success: false)
            updateToolStatus(in: &session, toolId: toolUseId, status: .error)

        default:
            return
        }
    }

    /// Process PreToolUse event for tool tracking
    nonisolated static func processPreToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId, let toolName = event.tool else { return }

        session.toolTracker.startTool(id: toolUseId, name: toolName)

        let toolExists = session.chatItems.contains { $0.id == toolUseId }
        if !toolExists {
            let input = extractToolInput(from: event.toolInput)
            let shouldAwaitPermission = event.shouldAwaitPermissionResponse
            let approvalMode = shouldAwaitPermission ? event.resolvedApprovalMode : nil
            let initialStatus: ToolStatus =
                shouldAwaitPermission ? .waitingForApproval : .running
            let placeholderItem = ChatHistoryItem(
                id: toolUseId,
                type: .toolCall(ToolCallItem(
                    agentType: session.agentType,
                    name: toolName,
                    input: input,
                    status: initialStatus,
                    approvalMode: approvalMode,
                    result: nil,
                    structuredResult: nil,
                    subagentTools: []
                )),
                timestamp: Date()
            )
            session.chatItems.append(placeholderItem)
            toolEventLogger.debug("Created placeholder tool entry for \(toolUseId.prefix(16), privacy: .public)")
        }
    }

    /// Process PostToolUse event for tool tracking
    nonisolated static func processPostToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId else { return }

        session.toolTracker.completeTool(id: toolUseId, success: true)
        updateToolStatus(in: &session, toolId: toolUseId, status: .success)
    }

    nonisolated static func processToolCompleted(
        session: inout SessionState,
        toolUseId: String,
        result: ToolCompletionResult
    ) {
        for i in 0..<session.chatItems.count {
            if session.chatItems[i].id == toolUseId,
               case .toolCall(var tool) = session.chatItems[i].type {
                tool.status = result.status
                tool.result = result.result
                tool.structuredResult = result.structuredResult
                session.chatItems[i] = ChatHistoryItem(
                    id: toolUseId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
                toolEventLogger.debug("Tool \(toolUseId.prefix(12), privacy: .public) completed with status: \(String(describing: result.status), privacy: .public)")
                return
            }
        }

        let count = session.chatItems.count
        toolEventLogger.warning("Completed tool \(toolUseId.prefix(16), privacy: .public) not found in chatItems (count: \(count))")
    }

    // MARK: - Subagent Tracking

    nonisolated static func processUnifiedSubagentEvent(
        event: UnifiedAgentEvent,
        session: inout SessionState
    ) {
        guard let tool = event.payload.tool,
              let toolUseId = tool.callId else { return }

        switch event.kind {
        case .permissionRequested, .toolStarted:
            if tool.toolName == "Task" {
                session.subagentState.startTask(
                    taskToolId: toolUseId,
                    description: tool.arguments["description"]
                )
                toolEventLogger.debug("Started unified Task subagent tracking: \(toolUseId.prefix(12), privacy: .public)")
            } else if session.subagentState.hasActiveSubagent {
                let subagentTool = SubagentToolCall(
                    id: toolUseId,
                    name: tool.toolName,
                    input: extractToolInput(from: tool.arguments),
                    status: event.kind == .permissionRequested ? .waitingForApproval : .running,
                    timestamp: event.timestamp
                )
                session.subagentState.addSubagentTool(subagentTool)
            }

        case .toolCompleted:
            if tool.toolName == "Task" {
                if let taskContext = session.subagentState.activeTasks[toolUseId] {
                    attachSubagentToolsToTask(
                        session: &session,
                        taskToolId: toolUseId,
                        subagentTools: taskContext.subagentTools
                    )
                }
                session.subagentState.stopTask(taskToolId: toolUseId)
            } else {
                session.subagentState.updateSubagentToolStatus(toolId: toolUseId, status: .success)
            }

        case .toolFailed:
            if tool.toolName == "Task" {
                if let taskContext = session.subagentState.activeTasks[toolUseId] {
                    attachSubagentToolsToTask(
                        session: &session,
                        taskToolId: toolUseId,
                        subagentTools: taskContext.subagentTools
                    )
                }
                session.subagentState.stopTask(taskToolId: toolUseId)
            } else {
                session.subagentState.updateSubagentToolStatus(toolId: toolUseId, status: .error)
            }

        default:
            return
        }
    }

    /// Process PreToolUse event for subagent tracking
    nonisolated static func processSubagentPreToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId else { return }

        if event.tool == "Task" {
            session.subagentState.startTask(taskToolId: toolUseId)
            toolEventLogger.debug("Started Task subagent tracking: \(toolUseId.prefix(12), privacy: .public)")
        } else if let toolName = event.tool, session.subagentState.hasActiveSubagent {
            toolEventLogger.debug("Adding subagent tool \(toolName, privacy: .public) to active Task")
            let input = extractToolInput(from: event.toolInput)
            let subagentTool = SubagentToolCall(
                id: toolUseId,
                name: toolName,
                input: input,
                status: .running,
                timestamp: Date()
            )
            session.subagentState.addSubagentTool(subagentTool)
        }
    }

    /// Process PostToolUse event for subagent tracking
    nonisolated static func processSubagentPostToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId else { return }

        if event.tool == "Task" {
            if let taskContext = session.subagentState.activeTasks[toolUseId] {
                toolEventLogger.debug("Task completing with \(taskContext.subagentTools.count) subagent tools")
                attachSubagentToolsToTask(
                    session: &session,
                    taskToolId: toolUseId,
                    subagentTools: taskContext.subagentTools
                )
            } else {
                toolEventLogger.debug("Task completing but no taskContext found for \(toolUseId.prefix(12), privacy: .public)")
            }
            session.subagentState.stopTask(taskToolId: toolUseId)
        } else {
            session.subagentState.updateSubagentToolStatus(toolId: toolUseId, status: .success)
        }
    }

    /// Transfer all active subagent tools before stop/interrupt
    nonisolated static func transferAllSubagentTools(session: inout SessionState, markAsInterrupted: Bool = false) {
        for (taskId, taskContext) in session.subagentState.activeTasks {
            var tools = taskContext.subagentTools
            if markAsInterrupted {
                for i in 0..<tools.count {
                    if tools[i].status == .running {
                        tools[i].status = .interrupted
                    }
                }
            }
            attachSubagentToolsToTask(
                session: &session,
                taskToolId: taskId,
                subagentTools: tools
            )
        }
        session.subagentState = SubagentState()
    }

    // MARK: - Tool Status Updates

    /// Update tool status in session's chat items
    nonisolated static func updateToolStatus(
        in session: inout SessionState,
        toolId: String,
        status: ToolStatus
    ) {
        for i in 0..<session.chatItems.count {
            if session.chatItems[i].id == toolId,
               case .toolCall(var tool) = session.chatItems[i].type,
               tool.status == .waitingForApproval || tool.status == .running {
                tool.status = status
                session.chatItems[i] = ChatHistoryItem(
                    id: toolId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
                return
            }
        }
        let count = session.chatItems.count
        toolEventLogger.warning("Tool \(toolId.prefix(16), privacy: .public) not found in chatItems (count: \(count))")
    }

    /// Find the next tool waiting for approval
    nonisolated static func findNextPendingTool(
        in session: SessionState,
        excluding toolId: String
    ) -> (id: String, name: String, input: [String: String], mode: ApprovalMode, timestamp: Date)? {
        for item in session.chatItems {
            if item.id == toolId { continue }
            if case .toolCall(let tool) = item.type, tool.status == .waitingForApproval {
                return (
                    id: item.id,
                    name: tool.name,
                    input: tool.input,
                    mode: tool.approvalMode ?? .nativeApp,
                    timestamp: item.timestamp
                )
            }
        }
        return nil
    }

    /// Mark all running tools as interrupted
    nonisolated static func markRunningToolsInterrupted(session: inout SessionState) {
        for i in 0..<session.chatItems.count {
            if case .toolCall(var tool) = session.chatItems[i].type,
               tool.status == .running {
                tool.status = .interrupted
                session.chatItems[i] = ChatHistoryItem(
                    id: session.chatItems[i].id,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
            }
        }
    }

    // MARK: - Private Helpers

    /// Attach subagent tools to a Task's ChatHistoryItem
    private nonisolated static func attachSubagentToolsToTask(
        session: inout SessionState,
        taskToolId: String,
        subagentTools: [SubagentToolCall]
    ) {
        guard !subagentTools.isEmpty else { return }

        for i in 0..<session.chatItems.count {
            if session.chatItems[i].id == taskToolId,
               case .toolCall(var tool) = session.chatItems[i].type {
                tool.subagentTools = subagentTools
                session.chatItems[i] = ChatHistoryItem(
                    id: taskToolId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
                toolEventLogger.debug("Attached \(subagentTools.count) subagent tools to Task \(taskToolId.prefix(12), privacy: .public)")
                break
            }
        }
    }

    /// Extract tool input from AnyCodable dictionary
    private nonisolated static func extractToolInput(from hookInput: [String: AnyCodable]?) -> [String: String] {
        var input: [String: String] = [:]
        guard let hookInput = hookInput else { return input }

        for (key, value) in hookInput {
            if let str = value.value as? String {
                input[key] = str
            } else if let num = value.value as? Int {
                input[key] = String(num)
            } else if let bool = value.value as? Bool {
                input[key] = bool ? "true" : "false"
            }
        }
        return input
    }

    private nonisolated static func extractToolInput(from toolArguments: [String: String]) -> [String: String] {
        toolArguments
    }
}
