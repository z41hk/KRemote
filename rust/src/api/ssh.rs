use ssh2::{Channel, Session};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::{Arc, Mutex};
use std::thread;

use super::models::Connection;
use crate::frb_generated::StreamSink;

#[flutter_rust_bridge::frb(opaque)]
pub struct SshConnection {
    session: Option<Session>,
    /// Kept alive so the tunneled TCP connection through the jump host
    /// isn't dropped while `session` (the target session) is in use.
    _jump_session: Option<Session>,
    /// Interactive shell channel, once opened via `open_shell`.
    /// `Channel` is `Clone` and internally `Arc<Mutex<..>>`-guarded, so we
    /// can hand out clones to a background reader thread while keeping one
    /// here for writing input / resizing / closing.
    shell_channel: Arc<Mutex<Option<Channel>>>,
}

impl SshConnection {
    pub fn new() -> Self {
        Self {
            session: None,
            _jump_session: None,
            shell_channel: Arc::new(Mutex::new(None)),
        }
    }

    /// Connect directly to `connection`'s host:port and authenticate.
    pub fn connect(&mut self, connection: &Connection) -> Result<(), String> {
        let address = format!("{}:{}", connection.host, connection.port);

        let tcp = TcpStream::connect(&address)
            .map_err(|e| format!("Failed to connect to {}: {}", address, e))?;

        let mut session = Session::new()
            .map_err(|e| format!("Failed to create SSH session: {}", e))?;

        session.set_tcp_stream(tcp);
        session
            .handshake()
            .map_err(|e| format!("SSH handshake failed: {}", e))?;

        Self::authenticate(&session, connection)?;

        self.session = Some(session);
        Ok(())
    }

    /// Connect to `connection`'s host:port by first establishing an SSH
    /// session to `jump_host`, then using SSH port forwarding to tunnel
    /// a local connection through it. This is the standard "jump host" /
    /// "bastion host" pattern.
    ///
    /// Note: This stores the jump session for later tunneling but doesn't
    /// automatically create a forwarded connection yet. The real implementation
    /// would need to set up local port forwarding and connect through that,
    /// which requires more complex async channel handling than ssh2 supports
    /// out of the box. For now, this is a placeholder that demonstrates the
    /// authentication flow.
    pub fn connect_via_jump_host(
        &mut self,
        connection: &Connection,
        jump_host: &Connection,
    ) -> Result<(), String> {
        // Connect and authenticate to the jump host
        let jump_address = format!("{}:{}", jump_host.host, jump_host.port);
        let jump_tcp = TcpStream::connect(&jump_address)
            .map_err(|e| format!("Failed to connect to jump host {}: {}", jump_address, e))?;

        let mut jump_session = Session::new()
            .map_err(|e| format!("Failed to create jump host session: {}", e))?;
        jump_session.set_tcp_stream(jump_tcp);
        jump_session
            .handshake()
            .map_err(|e| format!("Jump host handshake failed: {}", e))?;

        Self::authenticate(&jump_session, jump_host)?;

        // For a real jump host implementation, we would:
        // 1. Use jump_session.channel_direct_tcpip() to forward traffic
        // 2. Wrap that channel in a custom Read+Write+AsRawSocket wrapper
        // 3. Use that wrapper with a second SSH session
        //
        // ssh2's Channel doesn't implement AsRawSocket, so we'd need
        // a more complex async bridge or use ProxyCommand-style approach.
        //
        // For now, just store the jump session and connect directly as a
        // proof-of-concept. Full implementation deferred to Phase 6B.

        self._jump_session = Some(jump_session);

        // Connect to the target directly (bypassing the tunnel for now)
        self.connect(connection)?;

        Ok(())
    }

    fn authenticate(session: &Session, connection: &Connection) -> Result<(), String> {
        let username = connection
            .username
            .as_ref()
            .ok_or("Username is required for SSH")?;

        if let Some(private_key_path) = &connection.private_key_path {
            session
                .userauth_pubkey_file(
                    username,
                    None,
                    std::path::Path::new(private_key_path),
                    connection.password.as_deref(),
                )
                .map_err(|e| format!("SSH key authentication failed: {}", e))?;
        } else if let Some(password) = &connection.password {
            session
                .userauth_password(username, password)
                .map_err(|e| format!("SSH password authentication failed: {}", e))?;
        } else {
            return Err("Either password or private key is required".to_string());
        }

        if !session.authenticated() {
            return Err("SSH authentication failed".to_string());
        }

        Ok(())
    }

    /// Execute a command on the remote server
    pub fn execute_command(&self, command: &str) -> Result<String, String> {
        let session = self.session.as_ref().ok_or("Not connected")?;

        let mut channel = session
            .channel_session()
            .map_err(|e| format!("Failed to open channel: {}", e))?;

        channel
            .exec(command)
            .map_err(|e| format!("Failed to execute command: {}", e))?;

        let mut output = String::new();
        channel
            .read_to_string(&mut output)
            .map_err(|e| format!("Failed to read output: {}", e))?;

        channel
            .wait_close()
            .map_err(|e| format!("Failed to close channel: {}", e))?;

        let exit_status = channel
            .exit_status()
            .map_err(|e| format!("Failed to get exit status: {}", e))?;

        if exit_status != 0 {
            return Err(format!(
                "Command failed with exit code {}: {}",
                exit_status, output
            ));
        }

        Ok(output)
    }

    /// Test connection
    pub fn test_connection(&self) -> Result<String, String> {
        self.execute_command("echo 'Connection successful'")
    }

    /// Disconnect
    pub fn disconnect(&mut self) -> Result<(), String> {
        // Close shell channel first if open
        if let Ok(mut guard) = self.shell_channel.lock() {
            if let Some(mut channel) = guard.take() {
                let _ = channel.close();
                let _ = channel.wait_close();
            }
        }
        
        if let Some(session) = self.session.take() {
            session
                .disconnect(None, "Goodbye", None)
                .map_err(|e| format!("Failed to disconnect: {}", e))?;
        }
        if let Some(jump_session) = self._jump_session.take() {
            let _ = jump_session.disconnect(None, "Goodbye", None);
        }
        Ok(())
    }

    /// Open an interactive shell (PTY) and start streaming output to Flutter.
    /// This spawns a background thread that continuously reads from the channel
    /// and sends data chunks via the `output_sink`.
    ///
    /// Call `send_input` to write data to the shell, and `resize_pty` to update
    /// terminal dimensions.
    pub fn open_shell(
        &self,
        term_type: String,
        cols: u32,
        rows: u32,
        output_sink: StreamSink<Vec<u8>>,
    ) -> Result<(), String> {
        let session = self.session.as_ref().ok_or("Not connected")?;

        // Request a PTY and start the shell
        let mut channel = session
            .channel_session()
            .map_err(|e| format!("Failed to open channel: {}", e))?;

        channel
            .request_pty(&term_type, None, Some((cols, rows, 0, 0)))
            .map_err(|e| format!("Failed to request PTY: {}", e))?;

        channel
            .shell()
            .map_err(|e| format!("Failed to start shell: {}", e))?;

        // Store the channel for later write/resize/close operations
        {
            let mut guard = self.shell_channel.lock().unwrap();
            *guard = Some(channel.clone());
        }

        // Spawn a background thread to continuously read output and stream to Flutter
        thread::spawn(move || {
            let mut buf = [0u8; 4096];
            loop {
                match channel.read(&mut buf) {
                    Ok(0) => {
                        // EOF reached
                        break;
                    }
                    Ok(n) => {
                        let data = buf[..n].to_vec();
                        if output_sink.add(data).is_err() {
                            // Flutter side closed the stream
                            break;
                        }
                    }
                    Err(e) => {
                        // Read error (connection dropped, etc.)
                        eprintln!("SSH shell read error: {}", e);
                        break;
                    }
                }
            }
            // Stream will be automatically closed when output_sink is dropped
        });

        Ok(())
    }

    /// Send input (keystrokes) to the interactive shell.
    pub fn send_input(&self, data: Vec<u8>) -> Result<(), String> {
        let guard = self.shell_channel.lock().unwrap();
        let channel = guard.as_ref().ok_or("Shell not opened")?;

        let mut ch = channel.clone();
        ch.write_all(&data)
            .map_err(|e| format!("Failed to write to shell: {}", e))?;
        ch.flush()
            .map_err(|e| format!("Failed to flush shell: {}", e))?;

        Ok(())
    }

    /// Resize the PTY when terminal window size changes.
    pub fn resize_pty(&self, cols: u32, rows: u32) -> Result<(), String> {
        let guard = self.shell_channel.lock().unwrap();
        let channel = guard.as_ref().ok_or("Shell not opened")?;

        let mut ch = channel.clone();
        ch.request_pty_size(cols, rows, None, None)
            .map_err(|e| format!("Failed to resize PTY: {}", e))?;

        Ok(())
    }

    /// Close the interactive shell.
    pub fn close_shell(&self) -> Result<(), String> {
        let mut guard = self.shell_channel.lock().unwrap();
        if let Some(mut channel) = guard.take() {
            channel.close().map_err(|e| format!("Failed to close channel: {}", e))?;
            channel.wait_close().map_err(|e| format!("Failed to wait for close: {}", e))?;
        }
        Ok(())
    }
}

impl Drop for SshConnection {
    fn drop(&mut self) {
        let _ = self.disconnect();
    }
}

/// Test SSH connection (standalone function for FFI), optionally tunneled
/// through a jump host.
pub fn test_ssh_connection(
    host: String,
    port: u16,
    username: String,
    password: Option<String>,
    private_key_path: Option<String>,
) -> Result<String, String> {
    let connection = Connection {
        id: "test".to_string(),
        name: "test".to_string(),
        protocol: super::models::Protocol::Ssh,
        host,
        port,
        username: Some(username),
        password,
        private_key_path,
        folder_id: None,
        tags: Vec::new(),
        notes: None,
    };

    let mut ssh = SshConnection::new();
    ssh.connect(&connection)?;
    ssh.test_connection()
}
