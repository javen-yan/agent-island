import Foundation

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

    init(
        sessionId: String,
        cwd: String,
        agentType: AgentPlatform,
        transcriptPath: String? = nil,
        event: String,
        internalEvent: String? = nil,
        status: String,
        permissionMode: String? = nil,
        pid: Int? = nil,
        tty: String? = nil,
        tool: String? = nil,
        toolInput: [String: AnyCodable]? = nil,
        toolUseId: String? = nil,
        notificationType: String? = nil,
        message: String? = nil,
        extra: [String: AnyCodable]? = nil
    ) {
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
