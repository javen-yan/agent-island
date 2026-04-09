mod adapter;
mod dispatcher;
mod protocol;
mod socket_client;

use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::fs::OpenOptions;
use std::hash::{Hash, Hasher};
use std::io::{self, IsTerminal, Read};
use std::io::Write;
use std::path::PathBuf;
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use clap::Parser;
use dispatcher::dispatch;
use protocol::{AgentSource, BridgeProfile, PermissionDecision};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum BridgeLogLevel {
    Off,
    Error,
    Info,
    Debug,
    Trace,
}

impl BridgeLogLevel {
    fn from_str(value: &str) -> Self {
        match value.to_ascii_lowercase().as_str() {
            "off" => Self::Off,
            "error" => Self::Error,
            "debug" => Self::Debug,
            "trace" => Self::Trace,
            _ => Self::Info,
        }
    }
}

#[derive(Debug, Clone)]
struct BridgeLogConfig {
    enabled: bool,
    level: BridgeLogLevel,
    path: String,
}

impl BridgeLogConfig {
    fn from_env() -> Self {
        Self {
            enabled: env_flag("AGENT_ISLAND_BRIDGE_LOG_ENABLED").unwrap_or(true),
            level: std::env::var("AGENT_ISLAND_BRIDGE_LOG_LEVEL")
                .map(|value| BridgeLogLevel::from_str(&value))
                .unwrap_or(BridgeLogLevel::Info),
            path: bridge_log_path(),
        }
    }

    fn from_profile(profile: &BridgeProfile) -> Self {
        let mut config = Self::from_env();

        if let Ok(value) = std::env::var("AGENT_ISLAND_BRIDGE_LOG_ENABLED") {
            config.enabled = env_flag_value(&value).unwrap_or(profile.bridge_log_enabled);
        } else {
            config.enabled = profile.bridge_log_enabled;
        }

        if let Ok(value) = std::env::var("AGENT_ISLAND_BRIDGE_LOG_LEVEL") {
            config.level = BridgeLogLevel::from_str(&value);
        } else {
            config.level = BridgeLogLevel::from_str(&profile.bridge_log_level);
        }

        config
    }

    fn should_log(&self, level: BridgeLogLevel) -> bool {
        self.enabled && self.level != BridgeLogLevel::Off && level <= self.level
    }
}

#[derive(Debug, Parser)]
#[command(name = "agent-island-bridge")]
#[command(about = "Unified multi-agent hook bridge for Agent Island")]
struct Cli {
    #[arg(long, alias = "agent", default_value = "unknown")]
    source: String,

    #[arg(long, default_value = "/tmp/agent-island.sock")]
    socket: String,

    #[arg(long)]
    profile: Option<PathBuf>,
}

fn main() {
    let pid = process::id();
    let startup_log_config = BridgeLogConfig::from_env();
    log_process_event(&startup_log_config, BridgeLogLevel::Info, "start", pid, None);

    if let Err(error) = run() {
        let error_text = format!("{error:#}");
        log_process_event(
            &startup_log_config,
            BridgeLogLevel::Error,
            "error",
            pid,
            Some(&error_text),
        );
        eprintln!("{error_text}");
        process::exit(1);
    }

    log_process_event(&startup_log_config, BridgeLogLevel::Info, "exit", pid, Some("ok"));
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let source = AgentSource::from_str(&cli.source);

    let stdin_json = read_stdin_json()?;
    if stdin_json.trim().is_empty() {
        return Ok(());
    }

    let input: Value = serde_json::from_str(&stdin_json).context("invalid stdin json")?;
    let profile = load_profile(cli.profile, source)?;
    let log_config = BridgeLogConfig::from_profile(&profile);
    let adapter = adapter::adapter_for(source);
    let dispatch_result = dispatch(source, &input, &profile);
    log_bridge_event(
        &log_config,
        BridgeLogLevel::Debug,
        source.as_str(),
        "received",
        input.get("hook_event_name").and_then(Value::as_str),
        input.get("tool_use_id").and_then(Value::as_str),
        input.get("turn_id").and_then(Value::as_str),
        Some(&stdin_json),
        None,
    );
    let Some(payload) = dispatch_result.payload else {
        return Ok(());
    };
    let hook_event = dispatch_result.hook_event.unwrap_or_default();
    let status = dispatch_result
        .status
        .unwrap_or_else(|| adapter::HOOK_STATUS_PROCESSING.to_string());

    if let Some(permission_decision) = dispatch_result.permission_decision.as_deref() {
        socket_client::send_async(&cli.socket, &payload)?;

        if let Some(response) = adapter.map_permission_response(
            &PermissionDecision {
                decision: Some(permission_decision.to_string()),
                reason: Some("Auto-approved from Agent Island".to_string()),
                message: None,
                should_continue: None,
                stop_reason: None,
                patch: None,
            },
            &hook_event
        ) {
            let response_text = serde_json::to_string(&response.body)?;
            println!("{}", response_text);
            log_permission_response(
                &log_config,
                source.as_str(),
                &hook_event,
                permission_decision,
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                &response_text,
            );

            if std::env::var("RUST_LOG_PERMISSION_RESPONSE").is_ok() {
                eprintln!("permission_response_json={}", response_text);
            }
        } else {
            log_permission_response(
                &log_config,
                source.as_str(),
                &hook_event,
                permission_decision,
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                "<no-output>",
            );
        }
    } else if status == adapter::HOOK_STATUS_WAITING_FOR_APPROVAL {
        let decision = socket_client::send_sync(&cli.socket, &payload)?;
        if let Some(response) = adapter.map_permission_response(&decision, &hook_event) {
            let response_text = serde_json::to_string(&response.body)?;
            println!("{}", response_text);
            log_permission_response(
                &log_config,
                source.as_str(),
                &hook_event,
                decision.decision.as_deref().unwrap_or("none"),
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                &response_text,
            );

            if std::env::var("RUST_LOG_PERMISSION_RESPONSE").is_ok() {
                eprintln!("permission_response_json={}", response_text);
            }
        } else {
            log_permission_response(
                &log_config,
                source.as_str(),
                &hook_event,
                decision.decision.as_deref().unwrap_or("none"),
                payload.tool_use_id.as_deref(),
                input.get("turn_id").and_then(Value::as_str),
                &format!(
                    "<no-output> message={} continue={} stop_reason={} patch={}",
                    decision.message.as_deref().unwrap_or(""),
                    decision
                        .should_continue
                        .map(|value| value.to_string())
                        .unwrap_or_default(),
                    decision.stop_reason.as_deref().unwrap_or(""),
                    decision.has_patch(),
                ),
            );
        }
    } else {
        socket_client::send_async(&cli.socket, &payload)?;
    }

    Ok(())
}

fn log_permission_response(
    log_config: &BridgeLogConfig,
    source: &str,
    hook_event: &str,
    decision: &str,
    tool_use_id: Option<&str>,
    turn_id: Option<&str>,
    response_text: &str,
) {
    log_bridge_event(
        log_config,
        BridgeLogLevel::Info,
        source,
        "responded",
        Some(hook_event),
        tool_use_id,
        turn_id,
        None,
        Some(&format!("decision={} response={}", decision, response_text)),
    );
}

fn log_bridge_event(
    log_config: &BridgeLogConfig,
    level: BridgeLogLevel,
    source: &str,
    stage: &str,
    event: Option<&str>,
    tool_use_id: Option<&str>,
    turn_id: Option<&str>,
    stdin_body: Option<&str>,
    extra: Option<&str>,
) {
    if !log_config.should_log(level) {
        return;
    }

    let mut file = match OpenOptions::new().create(true).append(true).open(&log_config.path) {
        Ok(file) => file,
        Err(_) => return,
    };

    let ts = timestamp_millis();
    let stdin_sha = stdin_body.map(short_hash);
    let extra_sha = extra.map(short_hash);

    let _ = writeln!(
        file,
        "ts={} level={:?} source={} stage={} event={} tool_use_id={} turn_id={} stdin_sha={} extra_sha={} body={} extra={}",
        ts,
        level,
        source,
        stage,
        event.unwrap_or(""),
        tool_use_id.unwrap_or(""),
        turn_id.unwrap_or(""),
        stdin_sha.unwrap_or_default(),
        extra_sha.unwrap_or_default(),
        stdin_body.unwrap_or(""),
        extra.unwrap_or(""),
    );
}

fn log_process_event(
    log_config: &BridgeLogConfig,
    level: BridgeLogLevel,
    stage: &str,
    pid: u32,
    extra: Option<&str>,
) {
    if !log_config.should_log(level) {
        return;
    }

    let mut file = match OpenOptions::new().create(true).append(true).open(&log_config.path) {
        Ok(file) => file,
        Err(_) => return,
    };

    let ts = timestamp_millis();
    let extra_sha = extra.map(short_hash);

    let _ = writeln!(
        file,
        "ts={} level={:?} source=bridge stage={} pid={} extra_sha={} extra={}",
        ts,
        level,
        stage,
        pid,
        extra_sha.unwrap_or_default(),
        extra.unwrap_or(""),
    );
}

fn env_flag(key: &str) -> Option<bool> {
    std::env::var(key).ok().and_then(|value| env_flag_value(&value))
}

fn env_flag_value(value: &str) -> Option<bool> {
    match value.to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

fn timestamp_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default()
}

fn short_hash(value: &str) -> String {
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn bridge_log_path() -> String {
    if let Ok(path) = std::env::var("AGENT_ISLAND_BRIDGE_LOG") {
        return path;
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let directory = format!("{home}/Library/Application Support/AgentIsland/Logs");
    let _ = fs::create_dir_all(&directory);
    format!("{directory}/bridge.log")
}

fn read_stdin_json() -> Result<String> {
    if io::stdin().is_terminal() {
        return Ok(String::new());
    }

    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer)?;
    Ok(buffer)
}

fn load_profile(path: Option<PathBuf>, source: AgentSource) -> Result<BridgeProfile> {
    let path = path.unwrap_or_else(|| {
        PathBuf::from(format!(
            "{}/Library/Application Support/AgentIsland/Runtime/bridge-profiles/{}.json",
            std::env::var("HOME").unwrap_or_default(),
            source.as_str()
        ))
    });

    if !path.exists() {
        return Ok(BridgeProfile {
            response_mode: None,
            approval_tools: vec![],
            approval_command_patterns: vec![],
            auto_approve_tools: vec![],
            auto_approve_command_patterns: vec![],
            bridge_log_enabled: true,
            bridge_log_level: "info".to_string(),
        });
    }

    let contents = fs::read_to_string(&path)
        .with_context(|| format!("failed to read profile from {}", path.display()))?;
    let value: Value = serde_json::from_str(&contents)?;
    Ok(BridgeProfile::from_json(&value))
}

#[cfg(test)]
mod tests {
    use crate::adapter::adapter_for;
    use crate::protocol::{AgentSource, PermissionDecision};

    #[test]
    fn claude_permission_allow_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Claude);
        let response = adapter
            .map_permission_response(
                &PermissionDecision {
                    decision: Some("allow".to_string()),
                    reason: None,
                    message: None,
                    should_continue: None,
                    stop_reason: None,
                    patch: None,
                },
                "PermissionRequest",
            )
            .expect("expected response");
        let body = response.body;

        assert_eq!(
            body["hookSpecificOutput"]["hookEventName"].as_str(),
            Some("PermissionRequest")
        );
        assert_eq!(
            body["hookSpecificOutput"]["decision"]["behavior"].as_str(),
            Some("allow")
        );
    }

    #[test]
    fn claude_permission_deny_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Claude);
        let response = adapter
            .map_permission_response(
                &PermissionDecision {
                    decision: Some("deny".to_string()),
                    reason: Some("Nope".to_string()),
                    message: None,
                    should_continue: None,
                    stop_reason: None,
                    patch: None,
                },
                "PermissionRequest",
            )
            .expect("expected response");
        let body = response.body;

        assert_eq!(
            body["hookSpecificOutput"]["hookEventName"].as_str(),
            Some("PermissionRequest")
        );
        assert_eq!(
            body["hookSpecificOutput"]["decision"]["behavior"].as_str(),
            Some("deny")
        );
        assert_eq!(
            body["hookSpecificOutput"]["decision"]["message"].as_str(),
            Some("Nope")
        );
    }

    #[test]
    fn codex_permission_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Codex);
        let response = adapter.map_permission_response(
            &PermissionDecision {
                decision: Some("allow".to_string()),
                reason: Some("Approved".to_string()),
                message: None,
                should_continue: None,
                stop_reason: None,
                patch: None,
            },
            "PreToolUse",
        );
        assert!(response.is_none());
    }

    #[test]
    fn codex_deny_response_matches_block_shape() {
        let adapter = adapter_for(AgentSource::Codex);
        let response = adapter
            .map_permission_response(
                &PermissionDecision {
                    decision: Some("deny".to_string()),
                    reason: Some("Denied".to_string()),
                    message: None,
                    should_continue: None,
                    stop_reason: None,
                    patch: None,
                },
                "PreToolUse",
            )
            .expect("expected response");
        let body = response.body;

        assert_eq!(
            body["hookSpecificOutput"]["hookEventName"].as_str(),
            Some("PreToolUse")
        );
        assert_eq!(
            body["hookSpecificOutput"]["permissionDecision"].as_str(),
            Some("deny")
        );
        assert_eq!(
            body["hookSpecificOutput"]["permissionDecisionReason"].as_str(),
            Some("Denied")
        );
    }

    #[test]
    fn gemini_deny_response_matches_official_shape() {
        let adapter = adapter_for(AgentSource::Gemini);
        let response = adapter
            .map_permission_response(
                &PermissionDecision {
                    decision: Some("deny".to_string()),
                    reason: Some("Denied".to_string()),
                    message: None,
                    should_continue: None,
                    stop_reason: None,
                    patch: None,
                },
                "BeforeTool",
            )
            .expect("expected response");
        let body = response.body;

        assert_eq!(body["decision"].as_str(), Some("deny"));
        assert_eq!(body["reason"].as_str(), Some("Denied"));
    }

    #[test]
    fn gemini_allow_has_no_response_body() {
        let adapter = adapter_for(AgentSource::Gemini);
        let response = adapter.map_permission_response(
            &PermissionDecision {
                    decision: Some("allow".to_string()),
                    reason: None,
                    message: None,
                    should_continue: None,
                    stop_reason: None,
                    patch: None,
                },
                "BeforeTool",
            );
        assert!(response.is_none());
    }

    #[test]
    fn claude_permission_deny_prefers_message_field() {
        let adapter = adapter_for(AgentSource::Claude);
        let response = adapter
            .map_permission_response(
                &PermissionDecision {
                    decision: Some("deny".to_string()),
                    reason: None,
                    message: Some("Stop here".to_string()),
                    should_continue: Some(false),
                    stop_reason: Some("user_denied".to_string()),
                    patch: None,
                },
                "PermissionRequest",
            )
            .expect("expected response");
        let body = response.body;

        assert_eq!(
            body["hookSpecificOutput"]["decision"]["message"].as_str(),
            Some("Stop here")
        );
    }

    #[test]
    fn gemini_allow_with_patch_still_has_no_response_body() {
        let adapter = adapter_for(AgentSource::Gemini);
        let response = adapter.map_permission_response(
            &PermissionDecision {
                decision: Some("allow".to_string()),
                reason: None,
                message: None,
                should_continue: None,
                stop_reason: None,
                patch: Some(serde_json::json!({
                    "toolArguments": { "command": "echo ok" }
                })),
            },
            "BeforeTool",
        );
        assert!(response.is_none());
    }
}
