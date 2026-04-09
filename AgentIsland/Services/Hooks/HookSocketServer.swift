//
//  HookSocketServer.swift
//  Agent Island
//
//  Unix domain socket server for real-time hook events
//  Supports request/response for permission decisions
//

import Foundation
import os.log

/// Logger for hook socket server
private let logger = Logger(subsystem: "com.agentisland", category: "Hooks")

/// Raw hook payload received from the bridge.
struct RawHookEvent: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let agentType: AgentPlatform
    let transcriptPath: String?
    let event: String
    let internalEvent: String?
    let status: String
    let permissionMode: String?
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?
    let extra: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
        case transcriptPath = "transcript_path"
        case internalEvent = "internal_event"
        case permissionMode = "permission_mode"
        case cwd, event, status, pid, tty, tool
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case message
        case extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        agentType = AgentPlatform.from(rawValue: try container.decodeIfPresent(String.self, forKey: .agentType))
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        event = try container.decodeIfPresent(String.self, forKey: .event) ?? ""
        internalEvent = try container.decodeIfPresent(String.self, forKey: .internalEvent)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? HookEvent.Status.unknown.rawValue
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        toolInput = try container.decodeIfPresent([String: AnyCodable].self, forKey: .toolInput)
        toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        extra = try container.decodeIfPresent([String: AnyCodable].self, forKey: .extra)
    }
}

/// Domain hook event consumed by AgentIsland state and UI.
///
/// Stable integration contract:
/// - `internalEvent` is the primary field for AgentIsland business logic.
/// - `permissionMode` normalizes how a decision should be handled.
/// - `extra` carries agent-specific details that should not expand the core model.
/// - `event` remains available only for diagnostics and legacy translation fallback.
struct HookEvent: Sendable {
    let sessionId: String
    let cwd: String
    let agentType: AgentPlatform
    let transcriptPath: String?
    let event: String
    let internalEvent: String?
    let status: String
    let permissionMode: String?
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?
    let extra: [String: AnyCodable]?

    init(raw: RawHookEvent) {
        self.init(
            sessionId: raw.sessionId,
            cwd: raw.cwd,
            agentType: raw.agentType,
            transcriptPath: raw.transcriptPath,
            event: raw.event,
            internalEvent: raw.internalEvent,
            status: raw.status,
            permissionMode: raw.permissionMode,
            pid: raw.pid,
            tty: raw.tty,
            tool: raw.tool,
            toolInput: raw.toolInput,
            toolUseId: raw.toolUseId,
            notificationType: raw.notificationType,
            message: raw.message,
            extra: raw.extra
        )
    }

    /// Create a copy with updated toolUseId
    init(sessionId: String, cwd: String, agentType: AgentPlatform = .claude, transcriptPath: String?, event: String, internalEvent: String? = nil, status: String, permissionMode: String? = nil, pid: Int?, tty: String?, tool: String?, toolInput: [String: AnyCodable]?, toolUseId: String?, notificationType: String?, message: String?, extra: [String: AnyCodable]? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.agentType = agentType
        self.transcriptPath = transcriptPath
        self.event = event
        self.internalEvent = internalEvent
        self.status = status
        self.permissionMode = permissionMode
        self.pid = pid
        self.tty = tty
        self.tool = tool
        self.toolInput = toolInput
        self.toolUseId = toolUseId
        self.notificationType = notificationType
        self.message = message
        self.extra = extra
    }

    enum Status: String, Sendable {
        case waitingForApproval = "waiting_for_approval"
        case terminalApprovalRequired = "terminal_approval_required"
        case waitingForInput = "waiting_for_input"
        case runningTool = "running_tool"
        case processing = "processing"
        case starting = "starting"
        case compacting = "compacting"
        case ended = "ended"
        case notification = "notification"
        case unknown = "unknown"
    }

    enum EventName: String, Sendable {
        case notification = "Notification"
        case preCompact = "PreCompact"
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case stop = "Stop"
        case subagentStop = "SubagentStop"
        case beforeTool = "BeforeTool"
        case afterTool = "AfterTool"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case userPromptSubmit = "UserPromptSubmit"
        case permissionRequest = "PermissionRequest"
    }

    enum NotificationType: String, Sendable {
        case permissionPrompt = "permission_prompt"
        case idlePrompt = "idle_prompt"
        case unknown = "unknown"
    }

    enum ApprovalRequestType: Sendable {
        case none
        case app
        case terminal
    }

    enum InternalEventName: String, Sendable {
        case notification = "notification"
        case idlePrompt = "idle_prompt"
        case preCompact = "pre_compact"
        case sessionStarted = "session_started"
        case sessionEnded = "session_ended"
        case stopped = "stopped"
        case subagentStopped = "subagent_stopped"
        case toolWillRun = "tool_will_run"
        case toolDidRun = "tool_did_run"
        case userPromptSubmitted = "user_prompt_submitted"
        case permissionRequested = "permission_requested"
        case unknown = "unknown"
    }

    enum PermissionMode: String, Sendable {
        case nativeApp = "native_app"
        case terminal = "terminal"
    }
}

/// Response to send back to the hook.
/// The wire format stays backward-compatible with the legacy `decision/reason`
/// contract while exposing the wider unified action model to Swift callers.
struct HookResponse: Codable {
    let decision: String
    let reason: String?
    let version: String?
    let actionId: String?
    let targetEventId: String?
    let message: String?
    let `continue`: Bool?
    let stopReason: String?
    let patch: UnifiedAgentAction.Patch?
    let metadata: [String: String]?

    init(
        decision: String,
        reason: String? = nil,
        version: String? = nil,
        actionId: String? = nil,
        targetEventId: String? = nil,
        message: String? = nil,
        `continue`: Bool? = nil,
        stopReason: String? = nil,
        patch: UnifiedAgentAction.Patch? = nil,
        metadata: [String: String]? = nil
    ) {
        self.decision = decision
        self.reason = reason
        self.version = version
        self.actionId = actionId
        self.targetEventId = targetEventId
        self.message = message
        self.continue = `continue`
        self.stopReason = stopReason
        self.patch = patch
        self.metadata = metadata
    }

    init(action: UnifiedAgentAction) {
        self.init(
            decision: action.decision.rawValue,
            reason: action.message,
            version: action.version,
            actionId: action.actionId,
            targetEventId: action.targetEventId,
            message: action.message,
            continue: action.shouldContinue,
            stopReason: action.stopReason,
            patch: action.patch == .empty ? nil : action.patch,
            metadata: action.metadata.isEmpty ? nil : action.metadata
        )
    }

    enum CodingKeys: String, CodingKey {
        case decision
        case reason
        case version
        case actionId = "action_id"
        case targetEventId = "target_event_id"
        case message
        case `continue`
        case stopReason = "stop_reason"
        case patch
        case metadata
    }
}

/// Callback for hook events
typealias HookEventHandler = @Sendable (HookEvent) -> Void

/// Callback for permission response failures (socket died)
typealias PermissionFailureHandler = @Sendable (_ sessionId: String, _ toolUseId: String) -> Void

/// Unix domain socket server that receives events from Claude Code hooks
/// Uses GCD DispatchSource for non-blocking I/O
class HookSocketServer {
    static let shared = HookSocketServer()
    static let socketPath = "/tmp/agent-island.sock"

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var eventHandler: HookEventHandler?
    private var permissionFailureHandler: PermissionFailureHandler?
    private let queue = DispatchQueue(label: "com.agentisland.socket", qos: .userInitiated)
    private let pendingPermissionStore = PendingPermissionStore()
    private let toolUseIdCache = ToolUseIdCache()

    private init() {}

    /// Start the socket server
    func start(onEvent: @escaping HookEventHandler, onPermissionFailure: PermissionFailureHandler? = nil) {
        queue.async { [weak self] in
            self?.startServer(onEvent: onEvent, onPermissionFailure: onPermissionFailure)
        }
    }

    private func startServer(onEvent: @escaping HookEventHandler, onPermissionFailure: PermissionFailureHandler?) {
        guard serverSocket < 0 else { return }

        eventHandler = onEvent
        permissionFailureHandler = onPermissionFailure

        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            AppDiagnosticsLogger.log(.error, category: .hooks, "Failed to create socket errno=\(errno)")
            return
        }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            AppDiagnosticsLogger.log(.error, category: .hooks, "Failed to bind socket errno=\(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        chmod(Self.socketPath, 0o777)

        guard listen(serverSocket, 10) == 0 else {
            logger.error("Failed to listen: \(errno)")
            AppDiagnosticsLogger.log(.error, category: .hooks, "Failed to listen errno=\(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        logger.info("Listening on \(Self.socketPath, privacy: .public)")
        AppDiagnosticsLogger.log(.info, category: .hooks, "Listening on \(Self.socketPath)")

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        acceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
                self?.serverSocket = -1
            }
        }
        acceptSource?.resume()
    }

    /// Stop the socket server
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(Self.socketPath)

        for pending in pendingPermissionStore.removeAll() {
            close(pending.clientSocket)
        }
        toolUseIdCache.removeAll()
    }

    /// Respond to a pending permission request by toolUseId
    func respondToPermission(toolUseId: String, decision: String, reason: String? = nil) {
        queue.async { [weak self] in
            self?.sendPermissionResponse(toolUseId: toolUseId, decision: decision, reason: reason)
        }
    }

    /// Respond to permission by sessionId (finds the most recent pending for that session)
    func respondToPermissionBySession(sessionId: String, decision: String, reason: String? = nil) {
        queue.async { [weak self] in
            self?.sendPermissionResponseBySession(sessionId: sessionId, decision: decision, reason: reason)
        }
    }

    /// Respond with the unified action model by toolUseId.
    func respondToPermission(toolUseId: String, action: UnifiedAgentAction) {
        queue.async { [weak self] in
            self?.sendPermissionResponse(toolUseId: toolUseId, response: HookResponse(action: action))
        }
    }

    /// Respond with the unified action model using toolUseId first and sessionId as fallback.
    func respondToPermission(sessionId: String, toolUseId: String, action: UnifiedAgentAction) {
        queue.async { [weak self] in
            guard let self else { return }
            let response = HookResponse(action: action)
            if !self.sendPermissionResponse(toolUseId: toolUseId, response: response) {
                AppDiagnosticsLogger.log(.debug, category: .hooks, "Falling back to session response session=\(sessionId) tool=\(toolUseId)")
                self.sendPermissionResponseBySession(sessionId: sessionId, response: response)
            }
        }
    }

    /// Respond with the unified action model by sessionId.
    func respondToPermissionBySession(sessionId: String, action: UnifiedAgentAction) {
        queue.async { [weak self] in
            self?.sendPermissionResponseBySession(sessionId: sessionId, response: HookResponse(action: action))
        }
    }

    /// Cancel all pending permissions for a session (when Claude stops waiting)
    func cancelPendingPermissions(sessionId: String) {
        queue.async { [weak self] in
            self?.cleanupPendingPermissions(sessionId: sessionId)
        }
    }

    /// Check if there's a pending permission request for a session
    func hasPendingPermission(sessionId: String) -> Bool {
        pendingPermissionStore.contains(sessionId: sessionId)
    }

    /// Get the pending permission details for a session (if any)
    func getPendingPermission(sessionId: String) -> (toolName: String?, toolId: String?, toolInput: [String: AnyCodable]?)? {
        pendingPermissionStore.details(sessionId: sessionId)
    }

    /// Cancel a specific pending permission by toolUseId (when tool completes via terminal approval)
    func cancelPendingPermission(toolUseId: String) {
        queue.async { [weak self] in
            self?.cleanupSpecificPermission(toolUseId: toolUseId)
        }
    }

    private func cleanupSpecificPermission(toolUseId: String) {
        guard let pending = pendingPermissionStore.remove(toolUseId: toolUseId) else {
            return
        }

        logger.debug("Tool completed externally, closing socket for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
        close(pending.clientSocket)
    }

    private func cleanupPendingPermissions(sessionId: String) {
        let matching = pendingPermissionStore.removeAll(sessionId: sessionId)
        for pending in matching {
            logger.debug("Cleaning up stale permission for \(sessionId.prefix(8), privacy: .public) tool:\(pending.toolUseId.prefix(12), privacy: .public)")
            close(pending.clientSocket)
        }
    }

    // MARK: - Private

    private func acceptConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 131072)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 0.5 {
            let pollResult = poll(&pollFd, 1, 50)

            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)

                if bytesRead > 0 {
                    allData.append(contentsOf: buffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    break
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
            } else if pollResult == 0 {
                if !allData.isEmpty {
                    break
                }
            } else {
                break
            }
        }

        guard !allData.isEmpty else {
            close(clientSocket)
            return
        }

        let data = allData
        logger.debug("Event payload: \(String(data: data, encoding: .utf8) ?? "<invalid utf8>", privacy: .public)")
        AppDiagnosticsLogger.log(.trace, category: .hooks, "Received raw payload bytes=\(data.count)")

        guard let rawEvent = try? JSONDecoder().decode(RawHookEvent.self, from: data) else {
            logger.warning("Failed to parse event: \(String(data: data, encoding: .utf8) ?? "?", privacy: .public)")
            AppDiagnosticsLogger.log(.error, category: .hooks, "Failed to parse hook payload")
            close(clientSocket)
            return
        }
        let event = HookEvent(raw: rawEvent)

        logger.debug("Received: \(event.protocolDebugSummary, privacy: .public) for \(event.sessionId.prefix(8), privacy: .public)")
        AppDiagnosticsLogger.log(.debug, category: .hooks, "Received \(event.protocolDebugSummary) session=\(event.sessionId)")
        if event.usesLegacyEventFallback {
            logger.notice("Legacy hook fallback used for \(event.sessionId.prefix(8), privacy: .public) official:\(event.event, privacy: .public)")
            AppDiagnosticsLogger.log(.info, category: .hooks, "Legacy fallback session=\(event.sessionId) official=\(event.event)")
        }

        let permissionAdapter = AgentPermissionAdapterRegistry.shared.adapter(for: event.agentType)

        if permissionAdapter.shouldCacheToolUseId(for: event) {
            toolUseIdCache.store(for: event)
        }

        if event.isSessionEndLike {
            toolUseIdCache.removeAll(sessionId: event.sessionId)
        }

        if permissionAdapter.shouldAwaitPermissionResponse(for: event) {
            guard let toolUseId = permissionAdapter.resolveToolUseId(
                for: event,
                popCachedToolUseId: { [weak self] event in
                    self?.toolUseIdCache.pop(for: event)
                }
            ) else {
                logger.warning("Permission request missing tool_use_id for \(event.sessionId.prefix(8), privacy: .public) - no cache hit")
                AppDiagnosticsLogger.log(.error, category: .hooks, "Permission request missing tool_use_id session=\(event.sessionId)")
                close(clientSocket)
                eventHandler?(event)
                return
            }

            logger.debug("Permission request - keeping socket open for \(event.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
            AppDiagnosticsLogger.log(.debug, category: .hooks, "Keeping permission socket open session=\(event.sessionId) tool=\(toolUseId)")

            let updatedEvent = HookEvent(
                sessionId: event.sessionId,
                cwd: event.cwd,
                agentType: event.agentType,
                transcriptPath: event.transcriptPath,
                event: event.event,
                internalEvent: event.internalEvent,
                status: event.status,
                permissionMode: event.permissionMode,
                pid: event.pid,
                tty: event.tty,
                tool: event.tool,
                toolInput: event.toolInput,
                toolUseId: toolUseId,  // Use resolved toolUseId
                notificationType: event.notificationType,
                message: event.message,
                extra: event.extra
            )

            let pending = PendingPermission(
                sessionId: event.sessionId,
                toolUseId: toolUseId,
                clientSocket: clientSocket,
                event: updatedEvent,
                receivedAt: Date()
            )
            if let replaced = pendingPermissionStore.insert(pending) {
                logger.warning("Replacing pending permission for \(replaced.sessionId.prefix(8), privacy: .public) tool:\(replaced.toolUseId.prefix(12), privacy: .public)")
                close(replaced.clientSocket)
            }

            eventHandler?(updatedEvent)
            return
        } else {
            close(clientSocket)
        }

        eventHandler?(event)
    }

    private func sendPermissionResponse(toolUseId: String, decision: String, reason: String?) {
        sendPermissionResponse(
            toolUseId: toolUseId,
            response: HookResponse(decision: decision, reason: reason)
        )
    }

    @discardableResult
    private func sendPermissionResponse(toolUseId: String, response: HookResponse) -> Bool {
        guard let pending = pendingPermissionStore.remove(toolUseId: toolUseId) else {
            logger.debug("No pending permission for toolUseId: \(toolUseId.prefix(12), privacy: .public)")
            return false
        }

        guard let data = try? JSONEncoder().encode(response) else {
            close(pending.clientSocket)
            return false
        }
        if let responseBody = String(data: data, encoding: .utf8) {
            logger.debug("Permission response body: \(responseBody, privacy: .public)")
        }

        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(response.decision, privacy: .public) for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")
        AppDiagnosticsLogger.log(.info, category: .hooks, "Sent permission response decision=\(response.decision) session=\(pending.sessionId) tool=\(toolUseId)")

        let writeSuccess = writeAllBytes(
            to: pending.clientSocket,
            data: data,
            failureContext: "tool:\(toolUseId.prefix(12))"
        )

        close(pending.clientSocket)
        if !writeSuccess {
            permissionFailureHandler?(pending.sessionId, toolUseId)
        }
        return writeSuccess
    }

    private func sendPermissionResponseBySession(sessionId: String, decision: String, reason: String?) {
        sendPermissionResponseBySession(
            sessionId: sessionId,
            response: HookResponse(decision: decision, reason: reason)
        )
    }

    private func sendPermissionResponseBySession(sessionId: String, response: HookResponse) {
        guard let pending = pendingPermissionStore.removeMostRecent(sessionId: sessionId) else {
            logger.debug("No pending permission for session: \(sessionId.prefix(8), privacy: .public)")
            return
        }

        guard let data = try? JSONEncoder().encode(response) else {
            close(pending.clientSocket)
            permissionFailureHandler?(sessionId, pending.toolUseId)
            return
        }
        if let responseBody = String(data: data, encoding: .utf8) {
            logger.debug("Permission response body: \(responseBody, privacy: .public)")
        }

        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(response.decision, privacy: .public) for \(sessionId.prefix(8), privacy: .public) tool:\(pending.toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")
        AppDiagnosticsLogger.log(.info, category: .hooks, "Sent permission response decision=\(response.decision) session=\(sessionId) tool=\(pending.toolUseId)")

        let writeSuccess = writeAllBytes(
            to: pending.clientSocket,
            data: data,
            failureContext: "tool:\(pending.toolUseId.prefix(12))"
        )

        close(pending.clientSocket)

        if !writeSuccess {
            permissionFailureHandler?(sessionId, pending.toolUseId)
        }
    }

    private func writeAllBytes(to socket: Int32, data: Data, failureContext: String) -> Bool {
        var bytesRemaining = data.count
        var offset = 0

        while bytesRemaining > 0 {
            let writeResult = data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    logger.error("Failed to get data buffer address for \(failureContext)")
                    AppDiagnosticsLogger.log(.error, category: .hooks, "Failed to get buffer address context=\(failureContext)")
                    return -1
                }
                let startAddress = baseAddress.advanced(by: offset)
                return write(socket, startAddress, bytesRemaining)
            }

            if writeResult < 0 {
                logger.error("Write failed with errno: \(errno)")
                AppDiagnosticsLogger.log(.error, category: .hooks, "Socket write failed errno=\(errno) context=\(failureContext)")
                return false
            }

            if writeResult == 0 {
                logger.warning("Write wrote 0 bytes while data remained for \(failureContext)")
                AppDiagnosticsLogger.log(.error, category: .hooks, "Socket write wrote zero bytes context=\(failureContext)")
                return false
            }

            bytesRemaining -= writeResult
            offset += writeResult
        }

        logger.debug("Write succeeded: \(data.count) bytes for \(failureContext)")
        AppDiagnosticsLogger.log(.debug, category: .hooks, "Socket write succeeded bytes=\(data.count) context=\(failureContext)")
        return true
    }
}

// MARK: - AnyCodable for tool_input

/// Type-erasing codable wrapper for heterogeneous values
/// Used to decode JSON objects with mixed value types
struct AnyCodable: Codable, @unchecked Sendable {
    /// The underlying value (nonisolated(unsafe) because Any is not Sendable)
    nonisolated(unsafe) let value: Any

    /// Initialize with any value
    nonisolated init(_ value: Any) {
        self.value = value
    }

    /// Decode from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    /// Encode to JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}
