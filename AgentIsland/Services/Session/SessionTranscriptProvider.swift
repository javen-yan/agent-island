//
//  SessionTranscriptProvider.swift
//  Agent Island
//
//  Agent-specific transcript/history providers.
//  Keeps Claude JSONL parsing behind a provider boundary so the rest of the app
//  depends on agent capabilities instead of parser implementations.
//

import Foundation

typealias SessionToolResult = ConversationParser.ToolResult

struct SessionHistorySnapshot: Sendable {
    let messages: [ChatMessage]
    let completedToolIds: Set<String>
    let toolResults: [String: SessionToolResult]
    let structuredResults: [String: ToolResultData]
    let conversationInfo: ConversationInfo
    let phaseHint: SessionPhase?
}

struct SessionIncrementalSync: Sendable {
    let newMessages: [ChatMessage]
    let completedToolIds: Set<String>
    let toolResults: [String: SessionToolResult]
    let structuredResults: [String: ToolResultData]
    let clearDetected: Bool
    let conversationInfo: ConversationInfo
    let phaseHint: SessionPhase?
}

protocol SessionTranscriptProvider: Sendable {
    var agentType: AgentPlatform { get }
    func loadHistory(for session: SessionState) async -> SessionHistorySnapshot?
    func syncIncremental(for session: SessionState) async -> SessionIncrementalSync?
    func parseSubagentTools(agentId: String, cwd: String) async -> [SubagentToolInfo]
}

struct SessionTranscriptProviderRegistry {
    nonisolated static let shared = SessionTranscriptProviderRegistry()

    private let providers: [AgentPlatform: any SessionTranscriptProvider] = [
        .claude: ClaudeTranscriptProvider(),
        .codex: CodexTranscriptProvider()
    ]

    nonisolated func provider(for agentType: AgentPlatform) -> (any SessionTranscriptProvider)? {
        providers[agentType]
    }

    nonisolated func supportsHistory(for agentType: AgentPlatform) -> Bool {
        provider(for: agentType) != nil
    }
}

private struct ClaudeTranscriptProvider: SessionTranscriptProvider {
    let agentType: AgentPlatform = .claude

    func loadHistory(for session: SessionState) async -> SessionHistorySnapshot? {
        let snapshot = await ConversationParser.shared.parseFullSnapshot(
            sessionId: session.sessionId,
            cwd: session.cwd
        )

        return SessionHistorySnapshot(
            messages: snapshot.messages,
            completedToolIds: snapshot.completedToolIds,
            toolResults: snapshot.toolResults,
            structuredResults: snapshot.structuredResults,
            conversationInfo: snapshot.conversationInfo,
            phaseHint: nil
        )
    }

    func syncIncremental(for session: SessionState) async -> SessionIncrementalSync? {
        let result = await ConversationParser.shared.parseIncremental(
            sessionId: session.sessionId,
            cwd: session.cwd
        )
        let conversationInfo = await ConversationParser.shared.parse(
            sessionId: session.sessionId,
            cwd: session.cwd
        )

        return SessionIncrementalSync(
            newMessages: result.newMessages,
            completedToolIds: result.completedToolIds,
            toolResults: result.toolResults,
            structuredResults: result.structuredResults,
            clearDetected: result.clearDetected,
            conversationInfo: conversationInfo,
            phaseHint: nil
        )
    }

    func parseSubagentTools(agentId: String, cwd: String) async -> [SubagentToolInfo] {
        await ConversationParser.shared.parseSubagentTools(agentId: agentId, cwd: cwd)
    }
}

private actor CodexTranscriptProvider: SessionTranscriptProvider {
    let agentType: AgentPlatform = .codex

    private struct CacheEntry {
        var transcriptPath: String
        var messages: [ChatMessage]
        var conversationInfo: ConversationInfo
        var completedToolIds: Set<String>
        var toolResults: [String: SessionToolResult]
        var structuredResults: [String: ToolResultData]
        var phaseHint: SessionPhase?
    }

    private let fileManager = FileManager.default
    private var cache: [String: CacheEntry] = [:]

    func loadHistory(for session: SessionState) async -> SessionHistorySnapshot? {
        guard let parsed = parseTranscript(for: session) else {
            return nil
        }

        cache[session.sessionId] = CacheEntry(
            transcriptPath: parsed.transcriptPath,
            messages: parsed.messages,
            conversationInfo: parsed.conversationInfo,
            completedToolIds: parsed.completedToolIds,
            toolResults: parsed.toolResults,
            structuredResults: parsed.structuredResults,
            phaseHint: parsed.phaseHint
        )

        return SessionHistorySnapshot(
            messages: parsed.messages,
            completedToolIds: parsed.completedToolIds,
            toolResults: parsed.toolResults,
            structuredResults: parsed.structuredResults,
            conversationInfo: parsed.conversationInfo,
            phaseHint: parsed.phaseHint
        )
    }

    func syncIncremental(for session: SessionState) async -> SessionIncrementalSync? {
        guard let parsed = parseTranscript(for: session) else {
            return nil
        }

        let previous = cache[session.sessionId]
        cache[session.sessionId] = CacheEntry(
            transcriptPath: parsed.transcriptPath,
            messages: parsed.messages,
            conversationInfo: parsed.conversationInfo,
            completedToolIds: parsed.completedToolIds,
            toolResults: parsed.toolResults,
            structuredResults: parsed.structuredResults,
            phaseHint: parsed.phaseHint
        )

        let newMessages: [ChatMessage]
        if let previous {
            if previous.transcriptPath != parsed.transcriptPath {
                newMessages = parsed.messages
            } else if parsed.messages.count >= previous.messages.count {
                newMessages = Array(parsed.messages.dropFirst(previous.messages.count))
            } else {
                newMessages = parsed.messages
            }
        } else {
            newMessages = parsed.messages
        }

        return SessionIncrementalSync(
            newMessages: newMessages,
            completedToolIds: parsed.completedToolIds,
            toolResults: parsed.toolResults,
            structuredResults: parsed.structuredResults,
            clearDetected: false,
            conversationInfo: parsed.conversationInfo,
            phaseHint: parsed.phaseHint
        )
    }

    func parseSubagentTools(agentId: String, cwd: String) async -> [SubagentToolInfo] {
        []
    }

    private func parseTranscript(for session: SessionState) -> (
        messages: [ChatMessage],
        conversationInfo: ConversationInfo,
        completedToolIds: Set<String>,
        toolResults: [String: SessionToolResult],
        structuredResults: [String: ToolResultData],
        phaseHint: SessionPhase?,
        transcriptPath: String
    )? {
        guard let transcriptPath = resolveTranscriptPath(for: session),
              let content = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var messages: [ChatMessage] = []
        var firstUserMessage: String?
        var lastUserMessageDate: Date?
        var lastPreviewMessage: String?
        var lastPreviewRole: String?
        var completedToolIds = Set<String>()
        var toolResults: [String: SessionToolResult] = [:]
        var structuredResults: [String: ToolResultData] = [:]
        var phaseHint: SessionPhase?

        for (index, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if let nextPhaseHint = parsePhaseHint(from: json) {
                phaseHint = nextPhaseHint
            }

            if let message = parseMessage(
                from: json,
                lineIndex: index,
                lastPreviewMessage: &lastPreviewMessage,
                lastPreviewRole: &lastPreviewRole,
                completedToolIds: &completedToolIds,
                toolResults: &toolResults,
                structuredResults: &structuredResults
            ) {
                if message.role == .user {
                    let cleanedUserText = cleanedTitleText(textContent(for: message))
                    if firstUserMessage == nil, let cleanedUserText {
                        firstUserMessage = cleanedUserText
                    }
                    lastUserMessageDate = message.timestamp
                }

                messages.append(message)
            }
        }

        let summary = cleanedTitleText(loadThreadName(sessionId: session.sessionId))
        let conversationInfo = ConversationInfo(
            summary: summary,
            lastMessage: lastPreviewMessage,
            lastMessageRole: lastPreviewRole,
            lastToolName: nil,
            firstUserMessage: firstUserMessage,
            lastUserMessageDate: lastUserMessageDate
        )

        return (
            messages,
            conversationInfo,
            completedToolIds,
            toolResults,
            structuredResults,
            phaseHint,
            transcriptPath
        )
    }

    private func parsePhaseHint(from json: [String: Any]) -> SessionPhase? {
        guard let topLevelType = json["type"] as? String,
              topLevelType == "event_msg",
              let payload = json["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String else {
            return nil
        }

        switch payloadType {
        case "task_started":
            return .processing
        case "task_complete":
            return .waitingForInput
        case "turn_aborted":
            return .idle
        default:
            return nil
        }
    }

    private func parseMessage(
        from json: [String: Any],
        lineIndex: Int,
        lastPreviewMessage: inout String?,
        lastPreviewRole: inout String?,
        completedToolIds: inout Set<String>,
        toolResults: inout [String: SessionToolResult],
        structuredResults: inout [String: ToolResultData]
    ) -> ChatMessage? {
        guard let topLevelType = json["type"] as? String,
              let payload = json["payload"] as? [String: Any] else {
            return nil
        }

        let timestamp = parseDate(from: json["timestamp"] as? String) ?? Date()

        switch topLevelType {
        case "event_msg":
            return parseEventMessage(
                payload: payload,
                timestamp: timestamp,
                lineIndex: lineIndex,
                lastPreviewMessage: &lastPreviewMessage,
                lastPreviewRole: &lastPreviewRole,
                completedToolIds: &completedToolIds,
                toolResults: &toolResults,
                structuredResults: &structuredResults
            )
        case "response_item":
            return parseResponseItem(
                payload: payload,
                timestamp: timestamp,
                lineIndex: lineIndex,
                lastPreviewMessage: &lastPreviewMessage,
                lastPreviewRole: &lastPreviewRole,
                completedToolIds: &completedToolIds,
                toolResults: &toolResults,
                structuredResults: &structuredResults
            )
        default:
            return nil
        }
    }

    private func parseEventMessage(
        payload: [String: Any],
        timestamp: Date,
        lineIndex: Int,
        lastPreviewMessage: inout String?,
        lastPreviewRole: inout String?,
        completedToolIds: inout Set<String>,
        toolResults: inout [String: SessionToolResult],
        structuredResults: inout [String: ToolResultData]
    ) -> ChatMessage? {
        guard let payloadType = payload["type"] as? String else {
            return nil
        }

        if payloadType == "exec_command_end" {
            guard let callId = payload["call_id"] as? String else {
                return nil
            }

            let stdout = (payload["stdout"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = (payload["stderr"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let aggregatedOutput = (payload["aggregated_output"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (payload["status"] as? String) ?? "completed"
            let exitCode = payload["exit_code"] as? Int ?? 0
            let isError = status != "completed" || exitCode != 0

            completedToolIds.insert(callId)
            toolResults[callId] = SessionToolResult(
                content: aggregatedOutput,
                stdout: stdout,
                stderr: stderr,
                isError: isError
            )
            structuredResults[callId] = .bash(BashResult(
                stdout: stdout ?? "",
                stderr: stderr ?? "",
                interrupted: false,
                isImage: false,
                returnCodeInterpretation: nil,
                backgroundTaskId: nil
            ))

            return nil
        }

        switch payloadType {
        case "user_message":
            if let text = cleanedPreviewText(normalizedText(from: payload["message"])?.trimmingCharacters(in: .whitespacesAndNewlines)),
               !text.isEmpty {
                lastPreviewMessage = text
                lastPreviewRole = "user"
            }
            return nil
        case "agent_message":
            if let text = cleanedPreviewText(normalizedText(from: payload["message"])?.trimmingCharacters(in: .whitespacesAndNewlines)),
               !text.isEmpty {
                lastPreviewMessage = text
                lastPreviewRole = "assistant"
            }
            return nil
        default:
            return nil
        }
    }

    private func parseResponseItem(
        payload: [String: Any],
        timestamp: Date,
        lineIndex: Int,
        lastPreviewMessage: inout String?,
        lastPreviewRole: inout String?,
        completedToolIds: inout Set<String>,
        toolResults: inout [String: SessionToolResult],
        structuredResults: inout [String: ToolResultData]
    ) -> ChatMessage? {
        guard let payloadType = payload["type"] as? String else {
            return nil
        }

        switch payloadType {
        case "message":
            let message = parseResponseMessage(payload: payload, timestamp: timestamp, lineIndex: lineIndex)
            if let message,
               let text = cleanedPreviewText(textContent(for: message)),
               !text.isEmpty {
                lastPreviewMessage = text
                lastPreviewRole = roleName(for: message.role)
            }
            return message

        case "reasoning":
            return parseReasoningMessage(payload: payload, timestamp: timestamp, lineIndex: lineIndex)

        case "function_call":
            guard let callId = payload["call_id"] as? String,
                  let toolName = payload["name"] as? String else {
                return nil
            }

            let rawInput = decodeToolArguments(payload["arguments"])
            let normalizedToolCall = normalizedToolCall(name: toolName, input: rawInput)
            let block = MessageBlock.toolUse(
                ToolUseBlock(
                    id: callId,
                    name: normalizedToolCall.name,
                    input: normalizedToolCall.input
                )
            )
            return ChatMessage(
                id: "\(timestamp.timeIntervalSince1970)-\(lineIndex)-tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [block]
            )

        case "function_call_output":
            guard let callId = payload["call_id"] as? String else {
                return nil
            }

            let output = normalizedText(from: payload["output"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            completedToolIds.insert(callId)
            toolResults[callId] = SessionToolResult(
                content: output,
                stdout: nil,
                stderr: nil,
                isError: false
            )
            if let output, !output.isEmpty {
                structuredResults[callId] = .generic(GenericResult(rawContent: output, rawData: nil))
            }
            return nil

        default:
            return nil
        }
    }

    private func parseResponseMessage(
        payload: [String: Any],
        timestamp: Date,
        lineIndex: Int
    ) -> ChatMessage? {
        guard let roleName = payload["role"] as? String,
              roleName == "user" || roleName == "assistant",
              let role = ChatRole(rawValue: roleName) else {
            return nil
        }
        guard let content = payload["content"] as? [[String: Any]] else {
            return nil
        }

        let textBlocks = content.compactMap { item -> String? in
            guard let type = item["type"] as? String else { return nil }
            switch type {
            case "output_text", "input_text":
                return item["text"] as? String
            default:
                return nil
            }
        }

        let text = textBlocks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text = cleanedTitleText(text), !text.isEmpty else { return nil }

        if role == .user, text.contains("<turn_aborted>") {
            return ChatMessage(
                id: "\(timestamp.timeIntervalSince1970)-\(lineIndex)-interrupted-response",
                role: .system,
                timestamp: timestamp,
                content: [.interrupted]
            )
        }

        return ChatMessage(
            id: "\(timestamp.timeIntervalSince1970)-\(lineIndex)-\(role.rawValue)-response",
            role: role,
            timestamp: timestamp,
            content: [.text(text)]
        )
    }

    private func parseReasoningMessage(
        payload: [String: Any],
        timestamp: Date,
        lineIndex: Int
    ) -> ChatMessage? {
        let summaryText = normalizedReasoningSummary(from: payload["summary"])
        let contentText = normalizedText(from: payload["content"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text = cleanedPreviewText(summaryText ?? contentText), !text.isEmpty else {
            return nil
        }

        return ChatMessage(
            id: "\(timestamp.timeIntervalSince1970)-\(lineIndex)-reasoning",
            role: .assistant,
            timestamp: timestamp,
            content: [.thinking(text)]
        )
    }

    private func normalizedText(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }

        if let items = value as? [[String: Any]] {
            let text = items.compactMap { item -> String? in
                if let text = item["text"] as? String {
                    return text
                }
                if let content = item["content"] as? String {
                    return content
                }
                return nil
            }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }

        return nil
    }

    private func normalizedReasoningSummary(from value: Any?) -> String? {
        guard let items = value as? [[String: Any]] else {
            return nil
        }

        let text = items.compactMap { item -> String? in
            if let text = item["text"] as? String {
                return text
            }

            if let summary = item["summary"] as? String {
                return summary
            }

            if let content = item["content"] as? String {
                return content
            }

            return nil
        }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    private func decodeToolArguments(_ value: Any?) -> [String: String] {
        if let json = value as? String,
           let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return flattenDictionary(object)
        }

        if let object = value as? [String: Any] {
            return flattenDictionary(object)
        }

        return [:]
    }

    private func flattenDictionary(_ dictionary: [String: Any]) -> [String: String] {
        var flattened: [String: String] = [:]

        for (key, value) in dictionary {
            switch value {
            case let string as String:
                flattened[key] = string
            case let number as NSNumber:
                flattened[key] = number.stringValue
            case let nested as [String: Any]:
                if let data = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) {
                    flattened[key] = text
                }
            case let array as [Any]:
                if let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) {
                    flattened[key] = text
                }
            default:
                continue
            }
        }

        return flattened
    }

    private func normalizedToolCall(name: String, input: [String: String]) -> (name: String, input: [String: String]) {
        guard name == "exec_command" else {
            return (name, input)
        }

        var normalizedInput = input
        if normalizedInput["command"] == nil,
           let command = normalizedInput["cmd"],
           !command.isEmpty {
            normalizedInput["command"] = command
        }

        if normalizedInput["description"] == nil,
           let command = normalizedInput["command"],
           !command.isEmpty {
            let firstLine = command.components(separatedBy: .newlines).first ?? command
            normalizedInput["description"] = String(firstLine.prefix(80))
        }

        return ("Bash", normalizedInput)
    }

    private func resolveTranscriptPath(for session: SessionState) -> String? {
        if let transcriptPath = session.transcriptPath,
           fileManager.fileExists(atPath: transcriptPath) {
            return transcriptPath
        }

        let sessionsRoot = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions")
        guard let enumerator = fileManager.enumerator(atPath: sessionsRoot) else {
            return nil
        }

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".jsonl"),
                  relativePath.contains(session.sessionId) else {
                continue
            }

            let fullPath = (sessionsRoot as NSString).appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    private func loadThreadName(sessionId: String) -> String? {
        let indexPath = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/session_index.jsonl")
        guard let content = try? String(contentsOfFile: indexPath, encoding: .utf8) else {
            return nil
        }

        for line in content.components(separatedBy: .newlines).reversed() where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["id"] as? String == sessionId else {
                continue
            }

            let threadName = json["thread_name"] as? String
            return threadName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        return nil
    }

    private func parseDate(from value: String?) -> Date? {
        guard let value else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func textContent(for message: ChatMessage) -> String {
        message.content.compactMap { block in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private func cleanedTitleText(_ text: String?) -> String? {
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

        return text.nilIfEmpty
    }

    private func cleanedPreviewText(_ text: String?) -> String? {
        cleanedTitleText(text)
    }

    private func roleName(for role: ChatRole) -> String {
        switch role {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        case .system:
            return "system"
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
