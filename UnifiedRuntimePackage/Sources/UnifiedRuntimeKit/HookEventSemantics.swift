import Foundation

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
