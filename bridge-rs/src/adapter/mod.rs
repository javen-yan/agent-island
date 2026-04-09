mod claude;
mod codex;
mod gemini;
mod unknown;

use std::process;

use regex::Regex;
use serde_json::Value;

use crate::protocol::{AgentSource, BridgeProfile, HookPayload, PermissionDecision};

pub use claude::ClaudeAdapter;
pub use codex::CodexAdapter;
pub use gemini::GeminiAdapter;
pub use unknown::UnknownAdapter;

pub const HOOK_STATUS_WAITING_FOR_APPROVAL: &str = "waiting_for_approval";
pub const HOOK_STATUS_WAITING_FOR_INPUT: &str = "waiting_for_input";
pub const HOOK_STATUS_RUNNING_TOOL: &str = "running_tool";
pub const HOOK_STATUS_PROCESSING: &str = "processing";
pub const HOOK_STATUS_COMPACTING: &str = "compacting";
pub const HOOK_STATUS_ENDED: &str = "ended";
pub const HOOK_STATUS_NOTIFICATION: &str = "notification";
pub const HOOK_STATUS_UNKNOWN: &str = "unknown";

pub const INTERNAL_EVENT_NOTIFICATION: &str = "notification";
pub const INTERNAL_EVENT_IDLE_PROMPT: &str = "idle_prompt";
pub const INTERNAL_EVENT_PRE_COMPACT: &str = "pre_compact";
pub const INTERNAL_EVENT_SESSION_STARTED: &str = "session_started";
pub const INTERNAL_EVENT_SESSION_ENDED: &str = "session_ended";
pub const INTERNAL_EVENT_STOPPED: &str = "stopped";
pub const INTERNAL_EVENT_SUBAGENT_STOPPED: &str = "subagent_stopped";
pub const INTERNAL_EVENT_TOOL_WILL_RUN: &str = "tool_will_run";
pub const INTERNAL_EVENT_TOOL_DID_RUN: &str = "tool_did_run";
pub const INTERNAL_EVENT_USER_PROMPT_SUBMITTED: &str = "user_prompt_submitted";
pub const INTERNAL_EVENT_PERMISSION_REQUESTED: &str = "permission_requested";
pub const INTERNAL_EVENT_UNKNOWN: &str = "unknown";

pub const PERMISSION_MODE_NATIVE_APP: &str = "native_app";
pub const HOOK_EVENT_NOTIFICATION: &str = "Notification";
pub const HOOK_EVENT_PRE_COMPACT: &str = "PreCompact";
pub const HOOK_EVENT_SESSION_START: &str = "SessionStart";
pub const HOOK_EVENT_SESSION_END: &str = "SessionEnd";
pub const HOOK_EVENT_STOP: &str = "Stop";
pub const HOOK_EVENT_SUBAGENT_STOP: &str = "SubagentStop";
pub const HOOK_EVENT_BEFORE_TOOL: &str = "BeforeTool";
pub const HOOK_EVENT_AFTER_TOOL: &str = "AfterTool";
pub const HOOK_EVENT_PRE_TOOL_USE: &str = "PreToolUse";
pub const HOOK_EVENT_POST_TOOL_USE: &str = "PostToolUse";
pub const HOOK_EVENT_USER_PROMPT_SUBMIT: &str = "UserPromptSubmit";
pub const HOOK_EVENT_PERMISSION_REQUEST: &str = "PermissionRequest";

pub const NOTIFICATION_TYPE_PERMISSION_PROMPT: &str = "permission_prompt";
pub const NOTIFICATION_TYPE_IDLE_PROMPT: &str = "idle_prompt";

pub struct BridgeCapabilities {
    pub permission: PermissionCapability,
}

pub struct PermissionCapability {
    pub approval_request_events: &'static [&'static str],
}

#[derive(Debug, Clone)]
pub struct AgentRuntimeEvent {
    pub normalized: NormalizedInput,
    pub status: String,
    pub internal_event: String,
    pub permission_mode: Option<String>,
    pub extra: Value,
}

impl AgentRuntimeEvent {
    pub fn hook_event(&self) -> &str {
        &self.normalized.hook_event
    }

    pub fn into_payload(self, source: AgentSource, process_info: ProcessInfo) -> HookPayload {
        let session_id = non_empty_or(self.normalized.session_id.clone(), || {
            format!("unknown-{}", process::id())
        });
        let cwd = non_empty_or(self.normalized.cwd.clone(), || {
            std::env::current_dir()
                .ok()
                .map(|path| path.display().to_string())
                .unwrap_or_default()
        });

        build_payload(
            source,
            session_id,
            cwd,
            self.normalized.hook_event.clone(),
            self.internal_event,
            self.status,
            self.permission_mode,
            self.normalized.transcript_path.clone(),
            process_info.pid,
            process_info.tty,
            self.normalized.tool_name.clone(),
            self.normalized.tool_input.clone(),
            self.normalized.tool_use_id.clone(),
            self.normalized.notification_type.clone(),
            self.normalized.message.clone(),
            self.extra,
        )
    }
}

#[derive(Debug, Clone)]
pub struct AgentPermissionResponse {
    pub body: Value,
}

pub trait SourceAdapter {
    fn capabilities(&self) -> BridgeCapabilities;
    fn normalize_input(&self, input: &Value) -> NormalizedInput;
    fn should_emit_event(&self, normalized: &NormalizedInput) -> bool;
    fn status_for_event(&self, normalized: &NormalizedInput) -> String;
    fn process_info(&self, input: &Value) -> ProcessInfo;
    fn resolve_status(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> String {
        let base_status = self.status_for_event(normalized);
        if self.is_approval_request_event(normalized) || self.requires_approval(profile, normalized)
        {
            return HOOK_STATUS_WAITING_FOR_APPROVAL.to_string();
        }
        base_status
    }
    fn is_approval_request_event(&self, normalized: &NormalizedInput) -> bool {
        self.capabilities()
            .permission
            .approval_request_events
            .contains(&normalized.hook_event.as_str())
    }
    fn requires_approval(&self, profile: &BridgeProfile, normalized: &NormalizedInput) -> bool {
        default_requires_approval(profile, normalized)
    }
    fn auto_approve_decision(
        &self,
        profile: &BridgeProfile,
        normalized: &NormalizedInput,
    ) -> Option<&'static str> {
        if matches_auto_approve_command_patterns(profile, normalized.command_text.as_deref())
            || matches_auto_approve_tool(profile, normalized.tool_name.as_deref())
        {
            return Some("allow");
        }

        None
    }
    fn internal_event(
        &self,
        _profile: &BridgeProfile,
        normalized: &NormalizedInput,
        status: &str,
    ) -> String {
        default_internal_event_for(normalized, status)
    }
    fn permission_mode(
        &self,
        _profile: &BridgeProfile,
        normalized: &NormalizedInput,
        status: &str,
    ) -> Option<String> {
        default_permission_mode_for(normalized, status)
    }
    fn extra_payload(&self, _profile: &BridgeProfile, normalized: &NormalizedInput) -> Value {
        default_extra_payload(normalized)
    }
    fn map_event(&self, profile: &BridgeProfile, input: &Value) -> Option<AgentRuntimeEvent> {
        let normalized = self.normalize_input(input);
        if !self.should_emit_event(&normalized) {
            return None;
        }

        let status = self.resolve_status(profile, &normalized);
        let internal_event = self.internal_event(profile, &normalized, &status);
        let permission_mode = self.permission_mode(profile, &normalized, &status);
        let extra = self.extra_payload(profile, &normalized);

        Some(AgentRuntimeEvent {
            status,
            internal_event,
            permission_mode,
            extra,
            normalized,
        })
    }
    fn map_permission_response(
        &self,
        response: &PermissionDecision,
        hook_event: &str,
    ) -> Option<AgentPermissionResponse> {
        self.permission_response(response, hook_event)
            .map(|body| AgentPermissionResponse { body })
    }
    fn permission_response(&self, response: &PermissionDecision, hook_event: &str) -> Option<Value>;
}

pub fn log_unsupported_action_fields(
    provider: &str,
    hook_event: &str,
    fields: &[&str],
    response: &PermissionDecision,
) {
    if fields.is_empty() {
        return;
    }

    eprintln!(
        "{} response adapter downgraded unsupported fields for {}: {:?} decision={:?} message={:?} continue={:?} stop_reason={:?} patch={}",
        provider,
        hook_event,
        fields,
        response.decision,
        response.message,
        response.should_continue,
        response.stop_reason,
        response.has_patch()
    );
}

#[derive(Debug, Clone)]
pub struct NormalizedInput {
    pub hook_event: String,
    pub notification_type: Option<String>,
    pub tool_name: Option<String>,
    pub tool_input: Value,
    pub tool_use_id: Option<String>,
    pub session_id: Option<String>,
    pub cwd: Option<String>,
    pub transcript_path: Option<String>,
    pub message: Option<String>,
    pub command_text: Option<String>,
    pub escalation_requested: bool,
}

pub struct NormalizedInputOptions<'a> {
    pub tool_name_paths: &'a [&'a [&'a str]],
    pub tool_use_id_paths: &'a [&'a [&'a str]],
    pub session_id_keys: &'a [&'a str],
    pub cwd_keys: &'a [&'a str],
    pub transcript_path_keys: &'a [&'a str],
    pub notification_type_keys: &'a [&'a str],
    pub message_keys: &'a [&'a str],
}

impl Default for NormalizedInputOptions<'_> {
    fn default() -> Self {
        Self {
            tool_name_paths: &[
                &["tool_name"],
                &["toolName"],
                &["tool"],
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
        }
    }
}

pub fn normalize_event_name(value: &str) -> String {
    match value {
        HOOK_EVENT_SESSION_START | "session_start" => HOOK_EVENT_SESSION_START.to_string(),
        HOOK_EVENT_SESSION_END | "session_end" => HOOK_EVENT_SESSION_END.to_string(),
        HOOK_EVENT_NOTIFICATION | "notification" => HOOK_EVENT_NOTIFICATION.to_string(),
        HOOK_EVENT_STOP | "stop" => HOOK_EVENT_STOP.to_string(),
        HOOK_EVENT_BEFORE_TOOL
        | HOOK_EVENT_AFTER_TOOL
        | HOOK_EVENT_PRE_TOOL_USE
        | HOOK_EVENT_POST_TOOL_USE => value.to_string(),
        _ => value.to_string(),
    }
}

pub fn default_requires_approval(profile: &BridgeProfile, normalized: &NormalizedInput) -> bool {
    if normalized.escalation_requested {
        return true;
    }

    if matches_command_patterns(profile, normalized.command_text.as_deref()) {
        return true;
    }

    matches_approval_tool(profile, normalized.tool_name.as_deref())
}

pub fn matches_approval_tool(profile: &BridgeProfile, tool_name: Option<&str>) -> bool {
    tool_name
        .map(|name| profile.approval_tools.iter().any(|tool| tool == name))
        .unwrap_or(false)
}

pub fn matches_command_patterns(profile: &BridgeProfile, command_text: Option<&str>) -> bool {
    command_text
        .map(|command| {
            profile.approval_command_patterns.iter().any(|pattern| {
                Regex::new(pattern)
                    .map(|regex| regex.is_match(command))
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

pub fn matches_auto_approve_tool(profile: &BridgeProfile, tool_name: Option<&str>) -> bool {
    tool_name
        .map(|name| profile.auto_approve_tools.iter().any(|tool| tool == name))
        .unwrap_or(false)
}

pub fn matches_auto_approve_command_patterns(
    profile: &BridgeProfile,
    command_text: Option<&str>,
) -> bool {
    command_text
        .map(|command| {
            profile.auto_approve_command_patterns.iter().any(|pattern| {
                Regex::new(pattern)
                    .map(|regex| regex.is_match(command))
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

pub fn adapter_for(source: AgentSource) -> Box<dyn SourceAdapter + Send + Sync> {
    match source {
        AgentSource::Claude => Box::new(ClaudeAdapter),
        AgentSource::Codex => Box::new(CodexAdapter),
        AgentSource::Gemini => Box::new(GeminiAdapter),
        AgentSource::Unknown => Box::new(UnknownAdapter),
    }
}

pub fn default_status_for_event(hook_event: &str, notification_type: Option<&str>) -> String {
    match hook_event {
        HOOK_EVENT_NOTIFICATION => {
            if notification_type == Some(NOTIFICATION_TYPE_IDLE_PROMPT) {
                HOOK_STATUS_WAITING_FOR_INPUT.to_string()
            } else {
                HOOK_STATUS_NOTIFICATION.to_string()
            }
        }
        HOOK_EVENT_SESSION_START | HOOK_EVENT_STOP | HOOK_EVENT_SUBAGENT_STOP => {
            HOOK_STATUS_WAITING_FOR_INPUT.to_string()
        }
        HOOK_EVENT_SESSION_END => HOOK_STATUS_ENDED.to_string(),
        _ => HOOK_STATUS_PROCESSING.to_string(),
    }
}

pub fn default_internal_event_for(normalized: &NormalizedInput, status: &str) -> String {
    if status == HOOK_STATUS_WAITING_FOR_APPROVAL {
        return INTERNAL_EVENT_PERMISSION_REQUESTED.to_string();
    }

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
        HOOK_EVENT_BEFORE_TOOL | HOOK_EVENT_PRE_TOOL_USE => INTERNAL_EVENT_TOOL_WILL_RUN.to_string(),
        HOOK_EVENT_AFTER_TOOL | HOOK_EVENT_POST_TOOL_USE => INTERNAL_EVENT_TOOL_DID_RUN.to_string(),
        HOOK_EVENT_USER_PROMPT_SUBMIT => INTERNAL_EVENT_USER_PROMPT_SUBMITTED.to_string(),
        HOOK_EVENT_PERMISSION_REQUEST => INTERNAL_EVENT_PERMISSION_REQUESTED.to_string(),
        _ => INTERNAL_EVENT_UNKNOWN.to_string(),
    }
}

pub fn default_permission_mode_for(normalized: &NormalizedInput, status: &str) -> Option<String> {
    if status == HOOK_STATUS_WAITING_FOR_APPROVAL {
        if normalized.hook_event == HOOK_EVENT_PERMISSION_REQUEST {
            return Some(PERMISSION_MODE_NATIVE_APP.to_string());
        }
        return Some(PERMISSION_MODE_NATIVE_APP.to_string());
    }

    None
}

pub fn default_extra_payload(normalized: &NormalizedInput) -> Value {
    let mut extra = serde_json::Map::new();
    extra.insert(
        "officialEvent".to_string(),
        Value::String(normalized.hook_event.clone()),
    );
    if let Some(notification_type) = &normalized.notification_type {
        extra.insert(
            "notificationType".to_string(),
            Value::String(notification_type.clone()),
        );
    }
    if let Some(command_text) = &normalized.command_text {
        extra.insert("commandText".to_string(), Value::String(command_text.clone()));
    }
    if normalized.escalation_requested {
        extra.insert("escalationRequested".to_string(), Value::Bool(true));
    }
    Value::Object(extra)
}

pub fn build_payload(
    source: AgentSource,
    session_id: String,
    cwd: String,
    hook_event: String,
    internal_event: String,
    status: String,
    permission_mode: Option<String>,
    transcript_path: Option<String>,
    pid: Option<i64>,
    tty: Option<String>,
    tool: Option<String>,
    tool_input: Value,
    tool_use_id: Option<String>,
    notification_type: Option<String>,
    message: Option<String>,
    extra: Value,
) -> HookPayload {
    HookPayload {
        session_id,
        cwd,
        agent_type: source.as_str().to_string(),
        transcript_path,
        event: hook_event,
        internal_event,
        status,
        permission_mode,
        pid,
        tty,
        tool,
        tool_input,
        tool_use_id,
        notification_type,
        message,
        extra,
    }
}

fn non_empty_or<F>(value: Option<String>, fallback: F) -> String
where
    F: FnOnce() -> String,
{
    match value {
        Some(value) if !value.is_empty() => value,
        _ => fallback(),
    }
}

pub struct ProcessInfo {
    pub pid: Option<i64>,
    pub tty: Option<String>,
}

pub fn normalize_input_with_options(
    input: &Value,
    options: &NormalizedInputOptions<'_>,
) -> NormalizedInput {
    let tool_input = resolve_tool_input(input);
    let hook_event = normalize_event_name(&get_first_string(
        input,
        &[
            "hook_event_name",
            "hookEventName",
            "event_name",
            "eventName",
            "event",
            "type",
        ],
    ));
    let notification_type = get_first_string_opt(input, options.notification_type_keys);
    let tool_name = value_string_opt(input, options.tool_name_paths);
    let command_text = value_string_opt(&tool_input, &[&["command"], &["cmd"]]);
    let escalation_requested = value_string_opt(
        &tool_input,
        &[&["sandbox_permissions"], &["sandboxPermissions"]],
    )
    .map(|value| value == "require_escalated")
    .unwrap_or(false);

    NormalizedInput {
        hook_event,
        notification_type,
        tool_name,
        tool_input,
        tool_use_id: value_string_opt(input, options.tool_use_id_paths),
        session_id: get_first_string_opt(input, options.session_id_keys),
        cwd: get_first_string_opt(input, options.cwd_keys),
        transcript_path: get_first_string_opt(input, options.transcript_path_keys),
        message: get_first_string_opt(input, options.message_keys),
        command_text,
        escalation_requested,
    }
}

pub fn default_process_info(input: &Value) -> ProcessInfo {
    ProcessInfo {
        pid: first_i64(input, &["pid"]).or_else(|| Some(process::id() as i64)),
        tty: first_string(input, &["tty"]),
    }
}

pub fn first_string(input: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| input.get(*key).and_then(Value::as_str))
        .map(str::to_owned)
        .filter(|value| !value.is_empty())
}

fn first_i64(input: &Value, keys: &[&str]) -> Option<i64> {
    keys.iter()
        .find_map(|key| input.get(*key).and_then(Value::as_i64))
}

pub fn get_first_string(input: &Value, keys: &[&str]) -> String {
    get_first_string_opt(input, keys).unwrap_or_default()
}

pub fn get_first_string_opt(input: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| input.get(*key).and_then(Value::as_str))
        .map(str::to_owned)
        .filter(|value| !value.is_empty())
}

pub fn get_first_value(input: &Value, keys: &[&str]) -> Option<Value> {
    keys.iter().find_map(|key| input.get(*key).cloned())
}

pub fn value_string_opt(input: &Value, paths: &[&[&str]]) -> Option<String> {
    paths.iter().find_map(|path| {
        let mut current = input;
        for segment in *path {
            current = current.get(*segment)?;
        }
        current.as_str().map(str::to_owned)
    })
}

pub fn resolve_tool_input(input: &Value) -> Value {
    if let Some(value) = get_first_value(input, &["tool_input", "toolInput"]) {
        if let Some(resolved) = expand_arguments_object(&value) {
            return resolved;
        }
        return value;
    }

    if let Some(value) = get_first_value(input, &["arguments"]) {
        if let Some(parsed) = parse_json_string_value(&value) {
            return parsed;
        }
    }

    if let Some(value) = get_first_value(input, &["payload"]) {
        if let Some(resolved) = expand_arguments_object(&value) {
            return resolved;
        }
    }

    if let Some(value) = get_first_value(input, &["params"]) {
        if let Some(resolved) = expand_arguments_object(&value) {
            return resolved;
        }
    }

    Value::Object(Default::default())
}

fn expand_arguments_object(value: &Value) -> Option<Value> {
    if let Some(arguments) = value.get("arguments") {
        if let Some(parsed) = parse_json_string_value(arguments) {
            return Some(parsed);
        }
    }

    Some(value.clone())
}

fn parse_json_string_value(value: &Value) -> Option<Value> {
    let raw = value.as_str()?;
    serde_json::from_str(raw).ok()
}
