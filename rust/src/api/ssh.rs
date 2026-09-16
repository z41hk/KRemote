use ssh2::Session;
use std::io::Read;
use std::net::TcpStream;

use super::models::Connection;

#[flutter_rust_bridge::frb(opaque)]
pub struct SshConnection {
    session: Option<Session>,
}

impl SshConnection {
    pub fn new() -> Self {
        Self { session: None }
    }

    /// Connect to SSH server
    pub fn connect(&mut self, connection: &Connection) -> Result<(), String> {
        let address = format!("{}:{}", connection.host, connection.port);
        
        let tcp = TcpStream::connect(&address)
            .map_err(|e| format!("Failed to connect to {}: {}", address, e))?;

        let mut session = Session::new()
            .map_err(|e| format!("Failed to create SSH session: {}", e))?;

        session.set_tcp_stream(tcp);
        session.handshake()
            .map_err(|e| format!("SSH handshake failed: {}", e))?;

        // Authenticate
        let username = connection.username.as_ref()
            .ok_or("Username is required for SSH")?;

        if let Some(private_key_path) = &connection.private_key_path {
            // Key-based authentication
            session.userauth_pubkey_file(
                username,
                None,
                std::path::Path::new(private_key_path),
                connection.password.as_deref(),
            )
            .map_err(|e| format!("SSH key authentication failed: {}", e))?;
        } else if let Some(password) = &connection.password {
            // Password authentication
            session.userauth_password(username, password)
                .map_err(|e| format!("SSH password authentication failed: {}", e))?;
        } else {
            return Err("Either password or private key is required".to_string());
        }

        if !session.authenticated() {
            return Err("SSH authentication failed".to_string());
        }

        self.session = Some(session);
        Ok(())
    }

    /// Execute a command on the remote server
    pub fn execute_command(&self, command: &str) -> Result<String, String> {
        let session = self.session.as_ref()
            .ok_or("Not connected")?;

        let mut channel = session.channel_session()
            .map_err(|e| format!("Failed to open channel: {}", e))?;

        channel.exec(command)
            .map_err(|e| format!("Failed to execute command: {}", e))?;

        let mut output = String::new();
        channel.read_to_string(&mut output)
            .map_err(|e| format!("Failed to read output: {}", e))?;

        channel.wait_close()
            .map_err(|e| format!("Failed to close channel: {}", e))?;

        let exit_status = channel.exit_status()
            .map_err(|e| format!("Failed to get exit status: {}", e))?;

        if exit_status != 0 {
            return Err(format!("Command failed with exit code {}: {}", exit_status, output));
        }

        Ok(output)
    }

    /// Test connection
    pub fn test_connection(&self) -> Result<String, String> {
        self.execute_command("echo 'Connection successful'")
    }

    /// Disconnect
    pub fn disconnect(&mut self) -> Result<(), String> {
        if let Some(session) = self.session.take() {
            session.disconnect(None, "Goodbye", None)
                .map_err(|e| format!("Failed to disconnect: {}", e))?;
        }
        Ok(())
    }
}

impl Drop for SshConnection {
    fn drop(&mut self) {
        let _ = self.disconnect();
    }
}

/// Test SSH connection (standalone function for FFI)
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
        folder: None,
        tags: Vec::new(),
        notes: None,
    };

    let mut ssh = SshConnection::new();
    ssh.connect(&connection)?;
    ssh.test_connection()
}
