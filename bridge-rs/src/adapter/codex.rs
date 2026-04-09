use std::ffi::CStr;
use std::process::Command;

use serde_json::{json, Value};

use crate::protocol::{BridgeProfile, PermissionDecision};

use super::{
    default_extra_payload, default_requires_approval, first_string, get_first_string_opt,
    normalize_event_name, normalize_input_with_options,
    log_unsupported_action_fields, BridgeCapabilities, NormalizedInput, NormalizedInputOptions, PermissionCapability,
    ProcessInfo, SourceAdapter,
    HOOK_EVENT_POST_TOOL_USE, HOOK_EVENT_PRE_TOOL_USE, HOOK_EVENT_SESSION_END,
    HOOK_EVENT_SESSION_START, HOOK_EVENT_STOP, HOOK_EVENT_SUBAGENT_STOP,
    HOOK_EVENT_USER_PROMPT_SUBMIT, HOOK_STATUS_ENDED, HOOK_STATUS_PROCESSING,
    HOOK_STATUS_RUNNING_TOOL, HOOK_STATUS_WAITING_FOR_APPROVAL,
    HOOK_STATUS_WAITING_FOR_INPUT, INTERNAL_EVENT_PERMISSION_REQUESTED,
    INTERNAL_EVENT_SESSION_ENDED, INTERNAL_EVENT_SESSION_STARTED,
    INTERNAL_EVENT_STOPPED, INTERNAL_EVENT_SUBAGENT_STOPPED, INTERNAL_EVENT_TOOL_DID_RUN,
    INTERNAL_EVENT_TOOL_WILL_RUN, INTERNAL_EVENT_UNKNOWN,
    INTERNAL_EVENT_USER_PROMPT_SUBMITTED,
};

pub struct CodexAdapter;

const CODEX_TOOL_NAME_PATHS: &[&[&str]] = &[
    &["tool_name"],
    &["toolName"],
    &["tool"],
    &["payload", "name"],
    &["payload", "command"],
    &["params", "name"],
    &["params", "tool"],
    &["params", "tool_name"],
    &["params", "toolName"],
    &["params", "command"],
    &["name"],
];

const CODEX_TOOL_USE_ID_PATHS: &[&[&str]] = &[
    &["call_id"],
    &["callId"],
    &["tool_use_id"],
    &["toolUseId"],
    &["request_id"],
    &["requestId"],
    &["payload", "call_id"],
    &["payload", "callId"],
    &["params", "tool_use_id"],
    &["params", "toolUseId"],
    &["params", "call_id"],
    &["params", "callId"],
    &["params", "itemId"],
    &["params", "item_id"],
];

const CODEX_APPROVAL_EVENTS: &[&str] = &[HOOK_EVENT_PRE_TOOL_USE];

const CODEX_OPTIONS: NormalizedInputOptions<'static> = NormalizedInputOptions {
    tool_name_paths: CODEX_TOOL_NAME_PATHS,
    tool_use_id_paths: CODEX_TOOL_USE_ID_PATHS,
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
        "assistant_message",
        "last_assistant_message",
        "lastAssistantMessage",
    ],
};

impl SourceAdapter for CodexAdapter {
    fn capabilities(&self) -> BridgeCapabilities {
        BridgeCapabilities {
            permission: PermissionCapability {
                approval_request_events: &[],
            },
        }
    }

    fn normalize_input(&self, input: &Value) -> NormalizedInput {
        let mut normalized = normalize_input_with_options(input, &CODEX_OPTIONS);
        if let Some(method) = get_first_string_opt(input, &["method"]) {
            let normalized_method = normalize_event_name(&method);
            if is_approval_request_event(&normalized_method) {
                normalized.hook_event = normalized_method;
            }
        }
        normalized
    }

    fn should_emit_event(&self, normalized: &NormalizedInput) -> bool {
        match normalized.hook_event.as_str() {
            HOOK_EVENT_PRE_TOOL_USE | HOOK_EVENT_POST_TOOL_USE => {
                codex_tool_is_bash(normalized.tool_name.as_deref())
            }
            _ => true,
        }
    }

    fn status_for_event(&self, normalized: &NormalizedInput) -> String {
        match normalized.hook_event.as_str() {
            HOOK_EVENT_SESSION_START => HOOK_STATUS_WAITING_FOR_INPUT.to_string(),
            HOOK_EVENT_SESSION_END => HOOK_STATUS_ENDED.to_string(),
            HOOK_EVENT_STOP | HOOK_EVENT_SUBAGENT_STOP => HOOK_STATUS_WAITING_FOR_INPUT.to_string(),
            HOOK_EVENT_PRE_TOOL_USE => {
                if codex_requires_terminal_confirmation(normalized) {
                    HOOK_STATUS_WAITING_FOR_APPROVAL.to_string()
                } else {
                    HOOK_STATUS_RUNNING_TOOL.to_string()
                }
            }
            HOOK_EVENT_POST_TOOL_USE | HOOK_EVENT_USER_PROMPT_SUBMIT => {
                HOOK_STATUS_PROCESSING.to_string()
            }
            _ => HOOK_STATUS_PROCESSING.to_string(),
        }
    }

    fn process_info(&self, input: &Value) -> ProcessInfo {
        ProcessInfo {
            pid: Some(parent_pid() as i64),
            tty: resolve_codex_tty().or_else(|| first_string(input, &["tty"])),
        }
    }

    fn requires_approval(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> bool {
        default_requires_approval(profile, normalized)
    }

    fn internal_event(
        &self,
        _profile: &BridgeProfile,
        normalized: &NormalizedInput,
        status: &str,
    ) -> String {
        if status == HOOK_STATUS_WAITING_FOR_APPROVAL {
            return INTERNAL_EVENT_PERMISSION_REQUESTED.to_string();
        }

        match normalized.hook_event.as_str() {
            HOOK_EVENT_SESSION_START => INTERNAL_EVENT_SESSION_STARTED.to_string(),
            HOOK_EVENT_SESSION_END => INTERNAL_EVENT_SESSION_ENDED.to_string(),
            HOOK_EVENT_STOP => INTERNAL_EVENT_STOPPED.to_string(),
            HOOK_EVENT_SUBAGENT_STOP => INTERNAL_EVENT_SUBAGENT_STOPPED.to_string(),
            HOOK_EVENT_PRE_TOOL_USE => INTERNAL_EVENT_TOOL_WILL_RUN.to_string(),
            HOOK_EVENT_POST_TOOL_USE => INTERNAL_EVENT_TOOL_DID_RUN.to_string(),
            HOOK_EVENT_USER_PROMPT_SUBMIT => INTERNAL_EVENT_USER_PROMPT_SUBMITTED.to_string(),
            _ => INTERNAL_EVENT_UNKNOWN.to_string(),
        }
    }

    fn permission_mode(
        &self,
        _profile: &BridgeProfile,
        normalized: &NormalizedInput,
        status: &str,
    ) -> Option<String> {
        if status == HOOK_STATUS_WAITING_FOR_APPROVAL {
            let _ = normalized;
            return Some("terminal".to_string());
        }

        None
    }

    fn extra_payload(&self, _profile: &BridgeProfile, normalized: &NormalizedInput) -> Value {
        let mut extra = default_extra_payload(normalized);
        if let Value::Object(ref mut object) = extra {
            object.insert(
                "officialPermissionEvent".to_string(),
                Value::String(HOOK_EVENT_PRE_TOOL_USE.to_string()),
            );
            object.insert("toolMatcher".to_string(), Value::String("Bash".to_string()));
        }
        extra
    }

    fn permission_response(&self, response: &PermissionDecision, hook_event: &str) -> Option<Value> {
        let mapped = map_codex_decision(response.decision.as_deref())?;
        if std::env::var("RUST_LOG_PERMISSION_RESPONSE").is_ok() {
            eprintln!(
                "codex permission map: raw_decision={:?} mapped={:?} hook_event={}",
                response.decision, mapped, hook_event
            );
        }
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
        if response.message.is_some() && mapped != "deny" {
            unsupported.push("message");
        }
        log_unsupported_action_fields("codex", hook_event, &unsupported, response);

        let permission_reason = match mapped {
            "deny" => response.message_or_reason().or(Some("Denied from Agent Island")),
            "ask" => response.message_or_reason().or(Some("Need user confirmation")),
            _ => response.message_or_reason().or(Some("Approved from Agent Island")),
        };

        match mapped {
            // Official Codex docs only support deny/block for PreToolUse.
            // Allowing the tool should return exit 0 with no stdout.
            "allow" => None,
            // Prefer the documented deny shape over the legacy block response.
            "deny" => Some(json!({
                "hookSpecificOutput": {
                    "hookEventName": HOOK_EVENT_PRE_TOOL_USE,
                    "permissionDecision": "deny",
                    "permissionDecisionReason": permission_reason.unwrap_or("Denied from Agent Island")
                }
            })),
            // `ask` is parsed by Codex but not officially supported yet; fail open with no stdout.
            "ask" => None,
            _ => None,
        }
    }
}

fn map_codex_decision(decision: Option<&str>) -> Option<&'static str> {
    let decision = decision?;

    match decision {
        "allow" | "accept" | "acceptForSession" => Some("allow"),
        "deny" | "decline" | "cancel" => Some("deny"),
        "ask" => Some("ask"),
        _ => None,
    }
}

fn is_approval_request_event(event: &str) -> bool {
    CODEX_APPROVAL_EVENTS.contains(&event)
}

fn codex_tool_is_bash(tool_name: Option<&str>) -> bool {
    matches!(tool_name, Some(name) if name.eq_ignore_ascii_case("bash"))
}

fn codex_requires_terminal_confirmation(normalized: &NormalizedInput) -> bool {
    if !codex_tool_is_bash(normalized.tool_name.as_deref()) {
        return false;
    }

    let Some(command) = normalized.command_text.as_deref().map(str::trim) else {
        return false;
    };
    if command.is_empty() {
        return false;
    }

    let first = command
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .trim_matches(|c: char| c == '"' || c == '\'')
        .to_ascii_lowercase();

    matches!(
        first.as_str(),
        "rm" | "sudo" | "su" | "dd" | "mkfs" | "diskutil" | "shutdown" | "reboot" | "halt" | "chmod" | "chown"
    )
}

fn parent_pid() -> u32 {
    unsafe { libc::getppid() as u32 }
}

fn resolve_codex_tty() -> Option<String> {
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
