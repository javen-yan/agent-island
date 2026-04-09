import Testing
@testable import UnifiedRuntimeKit

@Test
func unifiedTranslatorMapsPermissionRequestToSemanticPermissionEvent() {
    let event = HookEvent(
        sessionId: "session-1",
        cwd: "/tmp/project",
        agentType: .codex,
        event: "PreToolUse",
        internalEvent: "permission_requested",
        status: "waiting_for_approval",
        permissionMode: "native_app",
        tool: "Bash",
        toolInput: ["command": AnyCodable("rm -rf /tmp/demo")],
        toolUseId: "tool-1"
    )

    let unified = event.unifiedEvent

    #expect(unified.kind == .permissionRequested)
    #expect(unified.payload.tool?.toolName == "Bash")
    #expect(unified.payload.permission?.requestId == "tool-1")
    #expect(unified.approvalMode == .nativeApp)
}

@Test
func unifiedTranslatorUsesLegacyFallbackWhenInternalEventIsMissing() {
    let event = HookEvent(
        sessionId: "session-2",
        cwd: "/tmp/project",
        agentType: .claude,
        event: "Notification",
        status: "notification",
        notificationType: "idle_prompt",
        message: "Waiting"
    )

    let unified = event.unifiedEvent

    #expect(unified.kind == .agentIdle)
    #expect(unified.payload.metadata["legacyFallback"] == "true")
}

@Test
func mappedSessionPhaseDerivesPermissionAndIdleTransitions() {
    let permissionEvent = UnifiedAgentEvent(
        provider: .claude,
        sessionId: "session-3",
        kind: .permissionRequested,
        payload: .init(
            session: .init(cwd: "/tmp/project", transcriptPath: nil, pid: nil, tty: nil),
            tool: .init(callId: "tool-2", toolName: "Bash", arguments: ["command": "ls"], risk: nil),
            permission: .init(requestId: "tool-2", sourceKind: "tool_call", providerEvent: nil),
            metadata: ["approvalMode": ApprovalMode.nativeApp.rawValue]
        )
    )
    let idleEvent = UnifiedAgentEvent(
        provider: .claude,
        sessionId: "session-3",
        kind: .agentIdle,
        payload: .init(notification: .init(type: "idle_prompt", title: "Idle"))
    )

    let permissionPhase = permissionEvent.mappedSessionPhase(currentPhase: .idle)
    let idlePhase = idleEvent.mappedSessionPhase(currentPhase: .processing)

    guard case .waitingForApproval(let context)? = permissionPhase else {
        Issue.record("Expected waitingForApproval phase")
        return
    }

    #expect(context.toolUseId == "tool-2")
    #expect(context.mode == .nativeApp)
    #expect(idlePhase == .waitingForInput)
}

@Test
func turnCompletedLeavesProcessingState() {
    let completedEvent = UnifiedAgentEvent(
        provider: .claude,
        sessionId: "session-4",
        kind: .turnCompleted,
        payload: .init(message: "Done")
    )

    let completedPhase = completedEvent.mappedSessionPhase(currentPhase: .processing)

    #expect(completedPhase == .waitingForInput)
}

@Test
func codexToolCompletedFallsBackToWaitingForInput() {
    let completedEvent = UnifiedAgentEvent(
        provider: .codex,
        sessionId: "session-5",
        kind: .toolCompleted,
        payload: .init(
            tool: .init(callId: "tool-5", toolName: "Bash", arguments: ["command": "rg --files"], risk: nil),
            result: .init(status: "processing", outputText: nil)
        )
    )

    let completedPhase = completedEvent.mappedSessionPhase(currentPhase: .processing)

    #expect(completedPhase == .waitingForInput)
}

@Test
func sessionPhaseSourcesPreferRuntimeOverTranscript() {
    var sources = SessionPhaseSources(transcript: .waitingForInput, runtime: .processing)

    #expect(sources.resolved(fallback: .idle) == .processing)

    sources.set(nil, for: .runtime)

    #expect(sources.resolved(fallback: .idle) == .waitingForInput)
}

@Test
func providerCapabilitiesDescribeCurrentCodexAndGeminiLimits() {
    let codex = ProviderCapabilities.baseline(for: .codex)
    let gemini = ProviderCapabilities.baseline(for: .gemini)

    #expect(codex.permissionSourceDescription(provider: .codex).contains("provider-side"))
    #expect(gemini.permissionSourceDescription(provider: .gemini).contains("allow-or-deny"))
    #expect(codex.supportsAskApproval == false)
    #expect(ProviderCapabilities.baseline(for: .claude).supportsAskApproval == true)
}
