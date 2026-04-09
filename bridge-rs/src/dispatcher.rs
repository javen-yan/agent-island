use serde_json::Value;

use crate::adapter::adapter_for;
use crate::protocol::{AgentSource, BridgeProfile};

pub struct DispatchResult {
    pub payload: Option<crate::protocol::HookPayload>,
    pub hook_event: Option<String>,
    pub status: Option<String>,
    pub permission_decision: Option<String>,
}

pub fn dispatch(source: AgentSource, input: &Value, profile: &BridgeProfile) -> DispatchResult {
    let adapter = adapter_for(source);
    let Some(mut runtime_event) = adapter.map_event(profile, input) else {
        return DispatchResult {
            payload: None,
            hook_event: None,
            status: None,
            permission_decision: None,
        };
    };

    let permission_decision = adapter
        .auto_approve_decision(profile, &runtime_event.normalized)
        .map(str::to_owned);

    if permission_decision.is_some() {
        let status = adapter.status_for_event(&runtime_event.normalized);
        runtime_event.status = status.clone();
        runtime_event.internal_event =
            adapter.internal_event(profile, &runtime_event.normalized, &status);
        runtime_event.permission_mode =
            adapter.permission_mode(profile, &runtime_event.normalized, &status);

        if let Value::Object(ref mut extra) = runtime_event.extra {
            extra.insert("autoApproved".to_string(), Value::Bool(true));
        }
    }

    let hook_event = runtime_event.hook_event().to_string();
    let status = runtime_event.status.clone();
    let process_info = adapter.process_info(input);
    let payload = runtime_event.into_payload(source, process_info);

    DispatchResult {
        payload: Some(payload),
        hook_event: Some(hook_event),
        status: Some(status),
        permission_decision,
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::dispatch;
    use crate::adapter::{
        HOOK_STATUS_WAITING_FOR_APPROVAL, INTERNAL_EVENT_IDLE_PROMPT,
        INTERNAL_EVENT_PERMISSION_REQUESTED,
    };
    use crate::protocol::{AgentSource, BridgeProfile};

    fn empty_profile() -> BridgeProfile {
        BridgeProfile {
            response_mode: None,
            approval_tools: vec![],
            approval_command_patterns: vec![],
            auto_approve_tools: vec![],
            auto_approve_command_patterns: vec![],
            bridge_log_enabled: true,
            bridge_log_level: "info".to_string(),
        }
    }

    #[test]
    fn claude_permission_request_maps_to_internal_permission_event() {
        let input = json!({
            "session_id": "claude-session",
            "cwd": "/tmp/project",
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": {
                "command": "ls -la"
            },
            "tool_use_id": "toolu_claude_123"
        });

        let result = dispatch(AgentSource::Claude, &input, &empty_profile());
        let payload = result.payload.expect("expected payload");

        assert_eq!(payload.event, "PermissionRequest");
        assert_eq!(payload.internal_event, INTERNAL_EVENT_PERMISSION_REQUESTED);
        assert_eq!(payload.status, HOOK_STATUS_WAITING_FOR_APPROVAL);
        assert_eq!(payload.permission_mode.as_deref(), Some("native_app"));
        assert_eq!(
            payload.extra.get("officialPermissionEvent").and_then(|v| v.as_str()),
            Some("PermissionRequest")
        );
    }

    #[test]
    fn codex_pre_tool_use_maps_to_running_tool_without_permission_prompt() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Bash",
                "command": "sed -n '1,40p' file.txt",
                "callId": "codex-call-123"
            }
        });

        let result = dispatch(AgentSource::Codex, &input, &empty_profile());
        let payload = result.payload.expect("expected payload");

        assert_eq!(payload.event, "PreToolUse");
        assert_eq!(payload.internal_event, crate::adapter::INTERNAL_EVENT_TOOL_WILL_RUN);
        assert_eq!(payload.status, crate::adapter::HOOK_STATUS_RUNNING_TOOL);
        assert_eq!(payload.permission_mode, None);
        assert_eq!(
            payload.extra.get("officialPermissionEvent").and_then(|v| v.as_str()),
            Some("PreToolUse")
        );
        assert_eq!(
            payload.extra.get("toolMatcher").and_then(|v| v.as_str()),
            Some("Bash")
        );
    }

    #[test]
    fn codex_read_tool_event_is_filtered_out() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Read",
                "file_path": "/tmp/demo.txt",
                "callId": "codex-call-read"
            }
        });

        let result = dispatch(AgentSource::Codex, &input, &empty_profile());
        assert!(result.payload.is_none());
    }

    #[test]
    fn gemini_before_tool_maps_to_internal_permission_event() {
        let input = json!({
            "session_id": "gemini-session",
            "cwd": "/tmp/project",
            "event": "BeforeTool",
            "tool_name": "write_file",
            "tool_input": {
                "path": "/tmp/demo.txt"
            },
            "tool_use_id": "gemini-call-123"
        });

        let result = dispatch(AgentSource::Gemini, &input, &empty_profile());
        let payload = result.payload.expect("expected payload");

        assert_eq!(payload.event, "BeforeTool");
        assert_eq!(payload.internal_event, INTERNAL_EVENT_PERMISSION_REQUESTED);
        assert_eq!(payload.status, HOOK_STATUS_WAITING_FOR_APPROVAL);
        assert_eq!(payload.permission_mode.as_deref(), Some("native_app"));
        assert_eq!(
            payload.extra.get("officialPermissionEvent").and_then(|v| v.as_str()),
            Some("BeforeTool")
        );
    }

    #[test]
    fn idle_notification_maps_to_internal_idle_prompt() {
        let input = json!({
            "session_id": "claude-session",
            "cwd": "/tmp/project",
            "hook_event_name": "Notification",
            "notification_type": "idle_prompt"
        });

        let result = dispatch(AgentSource::Claude, &input, &empty_profile());
        let payload = result.payload.expect("expected payload");

        assert_eq!(payload.internal_event, INTERNAL_EVENT_IDLE_PROMPT);
        assert_eq!(payload.permission_mode, None);
    }

    #[test]
    fn codex_auto_execute_rule_auto_approves_exact_command() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Bash",
                "command": "npm test",
                "callId": "codex-call-123"
            }
        });

        let profile = BridgeProfile {
            response_mode: Some("codex".to_string()),
            approval_tools: vec![],
            approval_command_patterns: vec![],
            auto_approve_tools: vec![],
            auto_approve_command_patterns: vec![r"^npm test$".to_string()],
            bridge_log_enabled: true,
            bridge_log_level: "info".to_string(),
        };

        let result = dispatch(AgentSource::Codex, &input, &profile);
        let payload = result.payload.expect("expected payload");

        assert_eq!(payload.tool_input.get("command").and_then(|v| v.as_str()), Some("npm test"));
        assert_eq!(result.permission_decision.as_deref(), Some("allow"));
        assert_eq!(payload.status, crate::adapter::HOOK_STATUS_RUNNING_TOOL);
        assert_eq!(payload.internal_event, crate::adapter::INTERNAL_EVENT_TOOL_WILL_RUN);
        assert_eq!(payload.permission_mode, None);
        assert_eq!(
            payload.extra.get("autoApproved").and_then(|v| v.as_bool()),
            Some(true)
        );
    }

    #[test]
    fn codex_escalation_alone_does_not_trigger_permission_prompt() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Bash",
                "command": "sed -n '1,120p' file.txt",
                "callId": "codex-call-456",
                "with_escalated_permissions": true
            }
        });

        let profile = BridgeProfile {
            response_mode: Some("codex".to_string()),
            approval_tools: vec![],
            approval_command_patterns: vec![],
            auto_approve_tools: vec![],
            auto_approve_command_patterns: vec![],
            bridge_log_enabled: true,
            bridge_log_level: "info".to_string(),
        };

        let result = dispatch(AgentSource::Codex, &input, &profile);
        let payload = result.payload.expect("expected payload");

        assert_eq!(result.permission_decision, None);
        assert_eq!(payload.status, crate::adapter::HOOK_STATUS_RUNNING_TOOL);
        assert_eq!(payload.internal_event, crate::adapter::INTERNAL_EVENT_TOOL_WILL_RUN);
        assert_eq!(payload.permission_mode, None);
    }

    #[test]
    fn codex_safe_pre_tool_use_stays_running_tool() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Bash",
                "command": "rg TODO src",
                "callId": "codex-call-safe"
            }
        });

        let result = dispatch(AgentSource::Codex, &input, &empty_profile());
        let payload = result.payload.expect("expected payload");

        assert_eq!(payload.status, crate::adapter::HOOK_STATUS_RUNNING_TOOL);
        assert_eq!(payload.internal_event, crate::adapter::INTERNAL_EVENT_TOOL_WILL_RUN);
        assert_eq!(payload.permission_mode, None);
    }

    #[test]
    fn codex_dangerous_command_maps_to_terminal_confirmation_state() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Bash",
                "command": "rm -rf /tmp/demo",
                "callId": "codex-call-danger"
            }
        });

        let profile = BridgeProfile {
            response_mode: Some("codex".to_string()),
            approval_tools: vec!["Bash".to_string()],
            approval_command_patterns: vec![r".+".to_string()],
            auto_approve_tools: vec![],
            auto_approve_command_patterns: vec![],
            bridge_log_enabled: true,
            bridge_log_level: "info".to_string(),
        };

        let result = dispatch(AgentSource::Codex, &input, &profile);
        let payload = result.payload.expect("expected payload");

        assert_eq!(result.permission_decision, None);
        assert_eq!(payload.status, crate::adapter::HOOK_STATUS_WAITING_FOR_APPROVAL);
        assert_eq!(payload.internal_event, crate::adapter::INTERNAL_EVENT_PERMISSION_REQUESTED);
        assert_eq!(payload.permission_mode.as_deref(), Some("terminal"));
    }

    #[test]
    fn codex_chmod_command_maps_to_terminal_confirmation_state() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Bash",
                "command": "chmod +x hello.sh",
                "callId": "codex-call-chmod"
            }
        });

        let result = dispatch(AgentSource::Codex, &input, &empty_profile());
        let payload = result.payload.expect("expected payload");

        assert_eq!(result.permission_decision, None);
        assert_eq!(payload.status, crate::adapter::HOOK_STATUS_WAITING_FOR_APPROVAL);
        assert_eq!(payload.internal_event, crate::adapter::INTERNAL_EVENT_PERMISSION_REQUESTED);
        assert_eq!(payload.permission_mode.as_deref(), Some("terminal"));
    }

    #[test]
    fn codex_approval_command_pattern_maps_to_terminal_confirmation_state() {
        let input = json!({
            "session_id": "codex-session",
            "cwd": "/tmp/project",
            "method": "PreToolUse",
            "params": {
                "name": "Bash",
                "command": "python manage.py migrate",
                "callId": "codex-call-pattern"
            }
        });

        let profile = BridgeProfile {
            response_mode: Some("codex".to_string()),
            approval_tools: vec![],
            approval_command_patterns: vec![r"manage\.py\s+migrate".to_string()],
            auto_approve_tools: vec![],
            auto_approve_command_patterns: vec![],
            bridge_log_enabled: true,
            bridge_log_level: "info".to_string(),
        };

        let result = dispatch(AgentSource::Codex, &input, &profile);
        let payload = result.payload.expect("expected payload");

        assert_eq!(payload.status, crate::adapter::HOOK_STATUS_WAITING_FOR_APPROVAL);
        assert_eq!(payload.internal_event, crate::adapter::INTERNAL_EVENT_PERMISSION_REQUESTED);
        assert_eq!(payload.permission_mode.as_deref(), Some("terminal"));
    }
}
