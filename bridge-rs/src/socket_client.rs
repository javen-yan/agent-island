use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use anyhow::Result;

use crate::protocol::{HookPayload, PermissionDecision};

pub fn send_async(socket_path: &str, payload: &HookPayload) -> Result<()> {
    let mut stream = match UnixStream::connect(socket_path) {
        Ok(stream) => stream,
        Err(_) => return Ok(()),
    };

    let body = serde_json::to_vec(payload)?;
    stream.write_all(&body)?;
    Ok(())
}

pub fn send_sync(socket_path: &str, payload: &HookPayload) -> Result<PermissionDecision> {
    let mut stream = match UnixStream::connect(socket_path) {
        Ok(stream) => stream,
        Err(_) => {
            return Ok(PermissionDecision {
                decision: None,
                reason: None,
                message: None,
                should_continue: None,
                stop_reason: None,
                patch: None,
            })
        }
    };
    stream.set_read_timeout(Some(Duration::from_secs(300)))?;

    let body = serde_json::to_vec(payload)?;
    stream.write_all(&body)?;

    let mut response = Vec::new();
    stream.read_to_end(&mut response)?;

    if response.is_empty() {
        return Ok(PermissionDecision {
            decision: None,
            reason: None,
            message: None,
            should_continue: None,
            stop_reason: None,
            patch: None,
        });
    }

    let json: serde_json::Value = serde_json::from_slice(&response)?;
    let message = json
        .get("message")
        .and_then(|v| v.as_str())
        .map(str::to_owned);

    Ok(PermissionDecision {
        decision: json
            .get("decision")
            .and_then(|v| v.as_str())
            .map(str::to_owned),
        reason: json
            .get("reason")
            .and_then(|v| v.as_str())
            .map(str::to_owned)
            .or_else(|| message.clone()),
        message,
        should_continue: json.get("continue").and_then(|v| v.as_bool()),
        stop_reason: json
            .get("stop_reason")
            .and_then(|v| v.as_str())
            .map(str::to_owned),
        patch: json.get("patch").cloned(),
    })
}
