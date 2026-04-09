use serde_json::Value;

use crate::protocol::PermissionDecision;

use super::{
    default_process_info, default_status_for_event, normalize_input_with_options,
    BridgeCapabilities, NormalizedInput, NormalizedInputOptions, PermissionCapability, ProcessInfo,
    SourceAdapter,
};

pub struct UnknownAdapter;

impl SourceAdapter for UnknownAdapter {
    fn capabilities(&self) -> BridgeCapabilities {
        BridgeCapabilities {
            permission: PermissionCapability {
                approval_request_events: &[],
            },
        }
    }

    fn normalize_input(&self, input: &Value) -> NormalizedInput {
        normalize_input_with_options(input, &NormalizedInputOptions::default())
    }

    fn should_emit_event(&self, _normalized: &NormalizedInput) -> bool {
        true
    }

    fn status_for_event(&self, normalized: &NormalizedInput) -> String {
        default_status_for_event(
            &normalized.hook_event,
            normalized.notification_type.as_deref(),
        )
    }

    fn process_info(&self, input: &Value) -> ProcessInfo {
        default_process_info(input)
    }

    fn permission_response(&self, _response: &PermissionDecision, _hook_event: &str) -> Option<Value> {
        None
    }
}
