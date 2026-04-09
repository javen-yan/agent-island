//
//  UnifiedHookEventTranslator.swift
//  Agent Island
//
//  Translates the current hook protocol into the product-facing unified protocol.
//

import Foundation

extension HookEvent {
    nonisolated var unifiedEvent: UnifiedAgentEvent {
        let resolvedKind = unifiedKind
        let session = UnifiedAgentEvent.SessionContext(
            cwd: cwd.isEmpty ? nil : cwd,
            transcriptPath: transcriptPath,
            pid: pid,
            tty: tty
        )
        let tool = unifiedToolContext
        let permission = unifiedPermissionContext(for: resolvedKind)
        let result = unifiedResultContext(for: resolvedKind)
        let notification = unifiedNotificationContext(for: resolvedKind)

        return UnifiedAgentEvent(
            provider: agentType,
            sessionId: sessionId,
            kind: resolvedKind,
            payload: .init(
                session: session,
                tool: tool,
                permission: permission,
                result: result,
                message: message,
                notification: notification,
                metadata: unifiedMetadata
            ),
            capabilityHints: unifiedCapabilityHints(for: resolvedKind),
            providerPayload: unifiedProviderPayload
        )
    }

    nonisolated var providerCapabilities: ProviderCapabilities {
        ProviderCapabilities.baseline(for: agentType)
    }

    private nonisolated var unifiedKind: UnifiedAgentEvent.Kind {
        switch internalEventValue {
        case .sessionStarted:
            return .sessionStarted
        case .sessionEnded:
            return .sessionEnded
        case .preCompact:
            return .sessionCompactionRequested
        case .notification:
            return .notification
        case .idlePrompt:
            return .agentIdle
        case .toolWillRun:
            switch approvalRequestType {
            case .none:
                return .toolStarted
            case .app, .terminal:
                return .permissionRequested
            }
        case .toolDidRun:
            return .toolCompleted
        case .userPromptSubmitted:
            return .turnInputSubmitted
        case .permissionRequested:
            return .permissionRequested
        case .stopped:
            return .turnCompleted
        case .subagentStopped:
            return .agentSubtaskCompleted
        case .unknown:
            return legacyUnifiedKind
        }
    }

    private nonisolated var legacyUnifiedKind: UnifiedAgentEvent.Kind {
        switch event {
        case HookEvent.EventName.sessionStart.rawValue:
            return .sessionStarted
        case HookEvent.EventName.sessionEnd.rawValue:
            return .sessionEnded
        case HookEvent.EventName.preCompact.rawValue:
            return .sessionCompactionRequested
        case HookEvent.EventName.notification.rawValue:
            if notificationType == HookEvent.NotificationType.idlePrompt.rawValue {
                return .agentIdle
            }
            return .notification
        case HookEvent.EventName.permissionRequest.rawValue:
            return .permissionRequested
        case HookEvent.EventName.beforeTool.rawValue, HookEvent.EventName.preToolUse.rawValue:
            switch approvalRequestType {
            case .none:
                return .toolStarted
            case .app, .terminal:
                return .permissionRequested
            }
        case HookEvent.EventName.afterTool.rawValue, HookEvent.EventName.postToolUse.rawValue:
            return .toolCompleted
        case HookEvent.EventName.userPromptSubmit.rawValue:
            return .turnInputSubmitted
        case HookEvent.EventName.subagentStop.rawValue:
            return .agentSubtaskCompleted
        case HookEvent.EventName.stop.rawValue:
            return .turnCompleted
        default:
            return .turnCompleted
        }
    }

    private nonisolated var unifiedToolContext: UnifiedAgentEvent.ToolContext? {
        guard let tool else { return nil }

        return UnifiedAgentEvent.ToolContext(
            callId: toolUseId,
            toolName: tool,
            arguments: stringifiedToolInput,
            risk: derivedRiskSummary
        )
    }

    private nonisolated func unifiedPermissionContext(
        for kind: UnifiedAgentEvent.Kind
    ) -> UnifiedAgentEvent.PermissionContext? {
        guard kind == .permissionRequested else { return nil }

        return UnifiedAgentEvent.PermissionContext(
            requestId: toolUseId ?? UUID().uuidString,
            sourceKind: tool == nil ? "session" : "tool_call",
            providerEvent: event.isEmpty ? nil : event
        )
    }

    private nonisolated func unifiedResultContext(
        for kind: UnifiedAgentEvent.Kind
    ) -> UnifiedAgentEvent.ResultContext? {
        switch kind {
        case .toolCompleted, .toolFailed, .turnCompleted, .turnFailed:
            return UnifiedAgentEvent.ResultContext(
                status: status,
                outputText: message
            )
        default:
            return nil
        }
    }

    private nonisolated func unifiedNotificationContext(
        for kind: UnifiedAgentEvent.Kind
    ) -> UnifiedAgentEvent.NotificationContext? {
        switch kind {
        case .notification, .agentIdle:
            return UnifiedAgentEvent.NotificationContext(
                type: notificationType,
                title: message
            )
        default:
            return nil
        }
    }

    private nonisolated func unifiedCapabilityHints(
        for kind: UnifiedAgentEvent.Kind
    ) -> UnifiedAgentEvent.CapabilityHints? {
        guard kind == .permissionRequested || kind == .toolStarted || kind == .toolCompleted else {
            return nil
        }

        let capabilities = providerCapabilities
        return UnifiedAgentEvent.CapabilityHints(
            supportsAllow: capabilities.toolControl.allow,
            supportsDeny: capabilities.toolControl.deny,
            supportsAsk: capabilities.supportsAskApproval,
            supportsArgumentPatch: capabilities.toolControl.rewriteArgs,
            supportsAdditionalContext: capabilities.sessionControl.injectStartContext,
            supportsStopTurn: capabilities.sessionControl.stopTurn
        )
    }

    private nonisolated var unifiedProviderPayload: UnifiedAgentEvent.ProviderPayload {
        var fields: [String: String] = [
            "status": status,
            "protocolDebugSummary": protocolDebugSummary
        ]

        if let internalEvent, !internalEvent.isEmpty {
            fields["internalEvent"] = internalEvent
        }
        if let permissionMode, !permissionMode.isEmpty {
            fields["permissionMode"] = permissionMode
        }
        if let notificationType, !notificationType.isEmpty {
            fields["notificationType"] = notificationType
        }
        if let toolUseId, !toolUseId.isEmpty {
            fields["toolUseId"] = toolUseId
        }
        if let extra {
            for (key, value) in extra {
                fields[key] = stringifyAnyCodable(value)
            }
        }

        return UnifiedAgentEvent.ProviderPayload(
            event: event.isEmpty ? nil : event,
            fields: fields
        )
    }

    private nonisolated var unifiedMetadata: [String: String] {
        var metadata: [String: String] = [
            "status": status,
            "agentType": agentType.rawValue
        ]

        if let permissionMode, !permissionMode.isEmpty {
            metadata["permissionMode"] = permissionMode
        }
        if let approvalMode = resolvedApprovalMode {
            metadata["approvalMode"] = approvalMode.rawValue
        }
        if let notificationType, !notificationType.isEmpty {
            metadata["notificationType"] = notificationType
        }
        if usesLegacyEventFallback {
            metadata["legacyFallback"] = "true"
        }

        return metadata
    }

    private nonisolated var stringifiedToolInput: [String: String] {
        guard let toolInput else { return [:] }
        return toolInput.mapValues(stringifyAnyCodable)
    }

    private nonisolated var derivedRiskSummary: UnifiedAgentEvent.RiskSummary? {
        guard let tool else { return nil }

        let arguments = stringifiedToolInput
        let command = arguments["command"] ?? arguments["cmd"] ?? ""
        let normalizedCommand = command.lowercased()
        let destructiveTokens = ["rm ", "rm-", "mv ", "chmod ", "chown ", "dd ", "mkfs", "shutdown", "reboot"]
        let destructive = destructiveTokens.contains { normalizedCommand.contains($0) }
        let filesystemWrite = [
            "write_file", "replace", "delete_file", "run_shell_script", "bash"
        ].contains(tool.lowercased()) || destructive
        let network = normalizedCommand.contains("curl ")
            || normalizedCommand.contains("wget ")
            || normalizedCommand.contains("http://")
            || normalizedCommand.contains("https://")
        let sandboxEscalation = arguments["sandbox_permissions"] == "require_escalated"
            || arguments["sandboxPermissions"] == "require_escalated"
        let secretsAccess = normalizedCommand.contains("keychain")
            || normalizedCommand.contains("aws ")
            || normalizedCommand.contains("gcloud ")
            || normalizedCommand.contains("op ")
        let openWorld = network || secretsAccess

        return UnifiedAgentEvent.RiskSummary(
            destructive: destructive,
            filesystemWrite: filesystemWrite,
            network: network,
            sandboxEscalation: sandboxEscalation,
            secretsAccess: secretsAccess,
            openWorld: openWorld
        )
    }
}

private nonisolated func stringifyAnyCodable(_ value: AnyCodable) -> String {
    stringifyAnyValue(value.value)
}

private nonisolated func stringifyAnyValue(_ value: Any) -> String {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    case let bool as Bool:
        return bool ? "true" : "false"
    case let array as [Any]:
        return array.map(stringifyAnyValue).joined(separator: ", ")
    case let dict as [String: Any]:
        let rendered = dict
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key)=\(stringifyAnyValue(value))" }
            .joined(separator: ", ")
        return "{\(rendered)}"
    default:
        return String(describing: value)
    }
}
