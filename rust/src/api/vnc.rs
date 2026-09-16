// Placeholder VNC module - VNC integration requires significant UI work
// (rendering video frames, input handling) that's beyond the current scope.
// This stub exists so the module can compile and we can add VNC connections
// to the vault, even if we can't connect to them yet.

use super::models::Connection;

/// Test VNC connection (not yet implemented)
pub fn test_vnc_connection(
    _host: String,
    _port: u16,
    _password: Option<String>,
) -> Result<String, String> {
    Err("VNC client not yet implemented - coming in Phase 2B".to_string())
}

/// Placeholder VNC connection struct for future implementation
#[flutter_rust_bridge::frb(opaque)]
pub struct VncConnection {
    _connection: Option<Connection>,
}

impl VncConnection {
    pub fn new() -> Self {
        Self { _connection: None }
    }

    pub fn connect(&mut self, _connection: &Connection) -> Result<(), String> {
        Err("VNC client not yet implemented - coming in Phase 2B".to_string())
    }

    pub fn disconnect(&mut self) -> Result<(), String> {
        Ok(())
    }
}
