use std::sync::OnceLock;

use super::models::{Connection, Protocol};
use super::ssh;
use super::vault::Vault;

/// Global vault instance, lazily initialized on first use.
/// A single Vault is shared across all FRB calls for the app's lifetime.
fn vault() -> &'static Vault {
    static VAULT: OnceLock<Vault> = OnceLock::new();
    VAULT.get_or_init(Vault::new)
}

/// Default path where the vault file is stored on disk.
/// Callers may also pass a custom path to the save/load functions.
#[flutter_rust_bridge::frb(sync)]
pub fn default_vault_path() -> String {
    let dir = dirs_next_config_dir();
    format!("{}/vault.dat", dir)
}

fn dirs_next_config_dir() -> String {
    #[cfg(target_os = "windows")]
    {
        std::env::var("APPDATA")
            .map(|p| format!("{}/KRemote", p.replace('\\', "/")))
            .unwrap_or_else(|_| ".".to_string())
    }
    #[cfg(not(target_os = "windows"))]
    {
        std::env::var("HOME")
            .map(|p| format!("{}/.config/kremote", p))
            .unwrap_or_else(|_| ".".to_string())
    }
}

/// Create a brand new vault protected by `master_password` and
/// immediately persist it to `path`.
pub fn create_vault(master_password: String, path: String) -> Result<(), String> {
    vault().create(&master_password)?;
    vault().save_to_file(&path)
}

/// Unlock (load and decrypt) an existing vault file from `path`.
pub fn unlock_vault(master_password: String, path: String) -> Result<(), String> {
    vault().load_from_file(&path, &master_password)
}

/// Lock the vault, clearing all decrypted data from memory.
#[flutter_rust_bridge::frb(sync)]
pub fn lock_vault() {
    vault().lock();
}

/// Whether the vault is currently unlocked.
#[flutter_rust_bridge::frb(sync)]
pub fn is_vault_unlocked() -> bool {
    vault().is_unlocked()
}

/// Whether a vault file already exists at `path`.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_exists(path: String) -> bool {
    std::path::Path::new(&path).exists()
}

/// Add a new connection and persist the vault to `path`.
pub fn add_connection(
    name: String,
    protocol: Protocol,
    host: String,
    port: u16,
    username: Option<String>,
    password: Option<String>,
    private_key_path: Option<String>,
    path: String,
) -> Result<Connection, String> {
    let mut connection = Connection::new(name, protocol, host, port);
    connection.username = username;
    connection.password = password;
    connection.private_key_path = private_key_path;

    vault().add_connection(connection.clone())?;
    vault().save_to_file(&path)?;

    Ok(connection)
}

/// Retrieve all connections currently stored in the unlocked vault.
pub fn get_connections() -> Result<Vec<Connection>, String> {
    vault().get_connections()
}

/// Delete a connection by ID and persist the change to `path`.
pub fn delete_connection(id: String, path: String) -> Result<(), String> {
    vault().delete_connection(&id)?;
    vault().save_to_file(&path)
}

/// Update an existing connection and persist the change to `path`.
pub fn update_connection(connection: Connection, path: String) -> Result<(), String> {
    vault().update_connection(connection)?;
    vault().save_to_file(&path)
}

/// Attempt to open an SSH connection using stored credentials for
/// `connection_id`, run a trivial command, then disconnect. Returns
/// a human-readable success message or an error describing what failed.
pub fn test_connection(connection_id: String) -> Result<String, String> {
    let connection = vault().get_connection(&connection_id)?;

    match connection.protocol {
        Protocol::Ssh => {
            let mut ssh_conn = ssh::SshConnection::new();
            ssh_conn.connect(&connection)?;
            ssh_conn.test_connection()
        }
        _ => Err("Only SSH connection testing is currently implemented".to_string()),
    }
}
