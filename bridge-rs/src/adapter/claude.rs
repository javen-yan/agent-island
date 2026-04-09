use std::ffi::CStr;
use std::process::Command;

use serde_json::{json, Value};

use crate::protocol::PermissionDecision;

use super::{
    default_extra_payload, first_string, normalize_input_with_options, BridgeCapabilities,
    log_unsupported_action_fields,
    NormalizedInput, NormalizedInputOptions, PermissionCapability, ProcessInfo, SourceAdapter,
    HOOK_EVENT_NOTIFICATION, HOOK_EVENT_PERMISSION_REQUEST, HOOK_EVENT_POST_TOOL_USE,
    HOOK_EVENT_PRE_COMPACT, HOOK_EVENT_PRE_TOOL_USE, HOOK_EVENT_SESSION_END,
    HOOK_EVENT_SESSION_START, HOOK_EVENT_STOP, HOOK_EVENT_SUBAGENT_STOP,
    HOOK_EVENT_USER_PROMPT_SUBMIT, HOOK_STATUS_COMPACTING, HOOK_STATUS_ENDED,
    HOOK_STATUS_NOTIFICATION, HOOK_STATUS_PROCESSING, HOOK_STATUS_RUNNING_TOOL,
    HOOK_STATUS_UNKNOWN, HOOK_STATUS_WAITING_FOR_APPROVAL, HOOK_STATUS_WAITING_FOR_INPUT,
    INTERNAL_EVENT_IDLE_PROMPT, INTERNAL_EVENT_NOTIFICATION,
    INTERNAL_EVENT_PERMISSION_REQUESTED, INTERNAL_EVENT_PRE_COMPACT,
    INTERNAL_EVENT_SESSION_ENDED, INTERNAL_EVENT_SESSION_STARTED,
    INTERNAL_EVENT_STOPPED, INTERNAL_EVENT_SUBAGENT_STOPPED, INTERNAL_EVENT_TOOL_DID_RUN,
    INTERNAL_EVENT_TOOL_WILL_RUN, INTERNAL_EVENT_UNKNOWN,
    INTERNAL_EVENT_USER_PROMPT_SUBMITTED, NOTIFICATION_TYPE_IDLE_PROMPT,
    NOTIFICATION_TYPE_PERMISSION_PROMPT, PERMISSION_MODE_NATIVE_APP,
};

pub struct ClaudeAdapter;

const CLAUDE_OPTIONS: NormalizedInputOptions<'static> = NormalizedInputOptions {
    tool_name_paths: &[
        &["tool_name"],
        &["toolName"],
        &["tool"],
        &["payload", "tool_name"],
        &["payload", "toolName"],
        &["payload", "name"],
        &["name"],
    ],
    tool_use_id_paths: &[
        &["tool_use_id"],
        &["toolUseId"],
        &["request_id"],
        &["requestId"],
        &["call_id"],
        &["callId"],
        &["payload", "tool_use_id"],
        &["payload", "toolUseId"],
        &["payload", "call_id"],
        &["payload", "callId"],
    ],
    session_id_keys: &["session_id", "sessionId"],
    cwd_keys: &["cwd", "working_directory"],
    transcript_path_keys: &["transcript_path", "transcriptPath"],
    notification_type_keys: &["notification_type", "notificationType"],
    message_keys: &[
        "prompt",
        "user_prompt",
        "userPrompt",
        "text",
        "message",
        "last_assistant_message",
        "lastAssistantMessage",
        "assistant_message",
    ],
};

impl SourceAdapter for ClaudeAdapter {
    fn capabilities(&self) -> BridgeCapabilities {
        BridgeCapabilities {
            permission: PermissionCapability {
                approval_request_events: &[],
            },
        }
    }

    fn normalize_input(&self, input: &Value) -> NormalizedInput {
        normalize_input_with_options(input, &CLAUDE_OPTIONS)
    }

    fn should_emit_event(&self, normalized: &NormalizedInput) -> bool {
        !(normalized.hook_event == HOOK_EVENT_NOTIFICATION
            && normalized.notification_type.as_deref() == Some(NOTIFICATION_TYPE_PERMISSION_PROMPT))
    }

    fn status_for_event(&self, normalized: &NormalizedInput) -> String {
        match normalized.hook_event.as_str() {
            HOOK_EVENT_SESSION_START => HOOK_STATUS_WAITING_FOR_INPUT.to_string(),
            HOOK_EVENT_SESSION_END => HOOK_STATUS_ENDED.to_string(),
            HOOK_EVENT_NOTIFICATION => {
                if normalized.notification_type.as_deref() == Some(NOTIFICATION_TYPE_IDLE_PROMPT) {
                    HOOK_STATUS_WAITING_FOR_INPUT.to_string()
                } else {
                    HOOK_STATUS_NOTIFICATION.to_string()
                }
            }
            HOOK_EVENT_STOP | HOOK_EVENT_SUBAGENT_STOP => HOOK_STATUS_WAITING_FOR_INPUT.to_string(),
            HOOK_EVENT_PRE_TOOL_USE => HOOK_STATUS_RUNNING_TOOL.to_string(),
            HOOK_EVENT_POST_TOOL_USE | HOOK_EVENT_USER_PROMPT_SUBMIT => {
                HOOK_STATUS_PROCESSING.to_string()
            }
            HOOK_EVENT_PRE_COMPACT => HOOK_STATUS_COMPACTING.to_string(),
            HOOK_EVENT_PERMISSION_REQUEST => HOOK_STATUS_WAITING_FOR_APPROVAL.to_string(),
            _ => HOOK_STATUS_UNKNOWN.to_string(),
        }
    }

    fn process_info(&self, input: &Value) -> ProcessInfo {
        ProcessInfo {
            pid: Some(parent_pid() as i64),
            tty: resolve_claude_tty().or_else(|| first_string(input, &["tty"])),
        }
    }

    fn internal_event(
        &self,
        _profile: &crate::protocol::BridgeProfile,
        normalized: &NormalizedInput,
        _status: &str,
    ) -> String {
        match normalized.hook_event.as_str() {
            HOOK_EVENT_NOTIFICATION => {
                if normalized.notification_type.as_deref() == Some(NOTIFICATION_TYPE_IDLE_PROMPT) {
                    INTERNAL_EVENT_IDLE_PROMPT.to_string()
                } else {
                    INTERNAL_EVENT_NOTIFICATION.to_string()
                }
            }
            HOOK_EVENT_PRE_COMPACT => INTERNAL_EVENT_PRE_COMPACT.to_string(),
            HOOK_EVENT_SESSION_START => INTERNAL_EVENT_SESSION_STARTED.to_string(),
            HOOK_EVENT_SESSION_END => INTERNAL_EVENT_SESSION_ENDED.to_string(),
            HOOK_EVENT_STOP => INTERNAL_EVENT_STOPPED.to_string(),
            HOOK_EVENT_SUBAGENT_STOP => INTERNAL_EVENT_SUBAGENT_STOPPED.to_string(),
            HOOK_EVENT_PRE_TOOL_USE => INTERNAL_EVENT_TOOL_WILL_RUN.to_string(),
            HOOK_EVENT_POST_TOOL_USE => INTERNAL_EVENT_TOOL_DID_RUN.to_string(),
            HOOK_EVENT_USER_PROMPT_SUBMIT => INTERNAL_EVENT_USER_PROMPT_SUBMITTED.to_string(),
            HOOK_EVENT_PERMISSION_REQUEST => INTERNAL_EVENT_PERMISSION_REQUESTED.to_string(),
            _ => INTERNAL_EVENT_UNKNOWN.to_string(),
        }
    }

    fn permission_mode(
        &self,
        _profile: &crate::protocol::BridgeProfile,
        normalized: &NormalizedInput,
        status: &str,
    ) -> Option<String> {
        if status == HOOK_STATUS_WAITING_FOR_APPROVAL
            || normalized.hook_event == HOOK_EVENT_PERMISSION_REQUEST
        {
            return Some(PERMISSION_MODE_NATIVE_APP.to_string());
        }

        None
    }

    fn extra_payload(
        &self,
        _profile: &crate::protocol::BridgeProfile,
        normalized: &NormalizedInput,
    ) -> Value {
        let mut extra = default_extra_payload(normalized);
        if let Value::Object(ref mut object) = extra {
            object.insert(
                "officialPermissionEvent".to_string(),
                Value::String(HOOK_EVENT_PERMISSION_REQUEST.to_string()),
            );
        }
        extra
    }

    fn permission_response(&self, response: &PermissionDecision, hook_event: &str) -> Option<Value> {
        let mut unsupported = Vec::new();
        if response.should_continue.is_some() {
            unsupported.push("continue");
        }
        if response.stop_reason.is_some() {
            unsupported.push("stop_reason");
        }
        if response.has_patch() {
            unsupported.push("patch");
        }
        if response.message.is_some() && response.decision.as_deref() != Some("deny") {
            unsupported.push("message");
        }
        log_unsupported_action_fields("claude", hook_event, &unsupported, response);

        match response.decision.as_deref() {
            Some("allow") => Some(json!({
                "hookSpecificOutput": {
                    "hookEventName": HOOK_EVENT_PERMISSION_REQUEST,
                    "decision": { "behavior": "allow" }
                }
            })),
            Some("deny") => Some(json!({
                "hookSpecificOutput": {
                    "hookEventName": HOOK_EVENT_PERMISSION_REQUEST,
                    "decision": {
                        "behavior": "deny",
                        "message": response.message_or_reason().unwrap_or("Denied by user via Agent Island")
                    }
                }
            })),
            _ => None,
        }
    }
}

fn parent_pid() -> u32 {
    unsafe { libc::getppid() as u32 }
}

fn resolve_claude_tty() -> Option<String> {
    let tty_from_parent = Command::new("ps")
        .args(["-p", &parent_pid().to_string(), "-o", "tty="])
        .output()
        .ok()
        .and_then(|output| {
            if !output.status.success() {
                return None;
            }

            let tty = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if tty.is_empty() || tty == "??" || tty == "-" {
                None
            } else if tty.starts_with("/dev/") {
                Some(tty)
            } else {
                Some(format!("/dev/{tty}"))
            }
        });

    tty_from_parent
        .or_else(|| tty_name_for_fd(libc::STDIN_FILENO))
        .or_else(|| tty_name_for_fd(libc::STDOUT_FILENO))
}

fn tty_name_for_fd(fd: i32) -> Option<String> {
    unsafe {
        let ptr = libc::ttyname(fd);
        if ptr.is_null() {
            return None;
        }

        CStr::from_ptr(ptr).to_str().ok().map(str::to_owned)
    }
}
