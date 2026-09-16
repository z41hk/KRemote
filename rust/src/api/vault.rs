use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use argon2::{Argon2, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{rand_core::RngCore, PasswordHash, SaltString};
use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

use super::models::Connection;

/// On-disk vault file format. `salt` and `password_hash` are stored
/// unencrypted (as they must be, to verify the master password and derive
/// the encryption key before anything else can be decrypted). The actual
/// connection data lives in `encrypted_data`, which is AES-256-GCM
/// encrypted with a key derived from the master password via Argon2id.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct VaultFile {
    salt: String,
    password_hash: String,
    /// Base64-encoded `nonce || ciphertext`
    encrypted_data: String,
}

struct VaultState {
    connections: Vec<Connection>,
    salt: String,
    password_hash: String,
}

pub struct Vault {
    state: Mutex<Option<VaultState>>,
    master_key: Mutex<Option<Vec<u8>>>,
}

impl Vault {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(None),
            master_key: Mutex::new(None),
        }
    }

    /// Create a brand new, empty vault protected by `master_password`.
    /// Does not write to disk - call `save_to_file` afterwards.
    pub fn create(&self, master_password: &str) -> Result<(), String> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();

        let password_hash = argon2
            .hash_password(master_password.as_bytes(), &salt)
            .map_err(|e| format!("Failed to hash password: {}", e))?
            .to_string();

        let salt_string = salt.to_string();
        let key = Self::derive_key(master_password, &salt_string)?;

        *self.state.lock().unwrap() = Some(VaultState {
            connections: Vec::new(),
            salt: salt_string,
            password_hash,
        });
        *self.master_key.lock().unwrap() = Some(key);

        Ok(())
    }

    /// Lock the vault, discarding the in-memory decryption key and data.
    pub fn lock(&self) {
        *self.master_key.lock().unwrap() = None;
        *self.state.lock().unwrap() = None;
    }

    /// Check if vault is currently unlocked and usable.
    pub fn is_unlocked(&self) -> bool {
        self.master_key.lock().unwrap().is_some()
    }

    /// Add a connection to the in-memory vault.
    pub fn add_connection(&self, connection: Connection) -> Result<(), String> {
        let mut state = self.state.lock().unwrap();
        let state = state.as_mut().ok_or("Vault is locked")?;
        state.connections.push(connection);
        Ok(())
    }

    /// Get all connections.
    pub fn get_connections(&self) -> Result<Vec<Connection>, String> {
        let state = self.state.lock().unwrap();
        let state = state.as_ref().ok_or("Vault is locked")?;
        Ok(state.connections.clone())
    }

    /// Get a specific connection by ID.
    pub fn get_connection(&self, id: &str) -> Result<Connection, String> {
        let state = self.state.lock().unwrap();
        let state = state.as_ref().ok_or("Vault is locked")?;
        state
            .connections
            .iter()
            .find(|c| c.id == id)
            .cloned()
            .ok_or_else(|| format!("Connection not found: {}", id))
    }

    /// Update an existing connection.
    pub fn update_connection(&self, connection: Connection) -> Result<(), String> {
        let mut state = self.state.lock().unwrap();
        let state = state.as_mut().ok_or("Vault is locked")?;

        if let Some(pos) = state.connections.iter().position(|c| c.id == connection.id) {
            state.connections[pos] = connection;
            Ok(())
        } else {
            Err(format!("Connection not found: {}", connection.id))
        }
    }

    /// Delete a connection by ID.
    pub fn delete_connection(&self, id: &str) -> Result<(), String> {
        let mut state = self.state.lock().unwrap();
        let state = state.as_mut().ok_or("Vault is locked")?;

        if let Some(pos) = state.connections.iter().position(|c| c.id == id) {
            state.connections.remove(pos);
            Ok(())
        } else {
            Err(format!("Connection not found: {}", id))
        }
    }

    /// Encrypt and persist the vault to disk.
    pub fn save_to_file(&self, path: &str) -> Result<(), String> {
        let state = self.state.lock().unwrap();
        let state = state.as_ref().ok_or("Vault is locked")?;
        let key = self.master_key.lock().unwrap();
        let key = key.as_ref().ok_or("Vault is locked")?;

        let json = serde_json::to_string(&state.connections)
            .map_err(|e| format!("Failed to serialize connections: {}", e))?;

        let encrypted_bytes = Self::encrypt_data(json.as_bytes(), key)?;
        let encrypted_data = general_purpose::STANDARD.encode(encrypted_bytes);

        let vault_file = VaultFile {
            salt: state.salt.clone(),
            password_hash: state.password_hash.clone(),
            encrypted_data,
        };

        let file_json = serde_json::to_string_pretty(&vault_file)
            .map_err(|e| format!("Failed to serialize vault file: {}", e))?;

        if let Some(parent) = std::path::Path::new(path).parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create directory: {}", e))?;
        }

        std::fs::write(path, file_json).map_err(|e| format!("Failed to write file: {}", e))?;

        Ok(())
    }

    /// Load and unlock a vault from an encrypted file on disk, verifying
    /// `master_password` against the stored hash before decrypting.
    pub fn load_from_file(&self, path: &str, master_password: &str) -> Result<(), String> {
        let file_json =
            std::fs::read_to_string(path).map_err(|e| format!("Failed to read file: {}", e))?;

        let vault_file: VaultFile = serde_json::from_str(&file_json)
            .map_err(|e| format!("Failed to parse vault file: {}", e))?;

        let parsed_hash = PasswordHash::new(&vault_file.password_hash)
            .map_err(|e| format!("Invalid password hash in vault file: {}", e))?;

        Argon2::default()
            .verify_password(master_password.as_bytes(), &parsed_hash)
            .map_err(|_| "Invalid master password".to_string())?;

        let key = Self::derive_key(master_password, &vault_file.salt)?;

        let encrypted_bytes = general_purpose::STANDARD
            .decode(&vault_file.encrypted_data)
            .map_err(|e| format!("Failed to decode vault data: {}", e))?;

        let decrypted = Self::decrypt_data(&encrypted_bytes, &key)?;

        let connections: Vec<Connection> = serde_json::from_slice(&decrypted)
            .map_err(|e| format!("Failed to parse connections: {}", e))?;

        *self.state.lock().unwrap() = Some(VaultState {
            connections,
            salt: vault_file.salt,
            password_hash: vault_file.password_hash,
        });
        *self.master_key.lock().unwrap() = Some(key);

        Ok(())
    }

    fn derive_key(password: &str, salt: &str) -> Result<Vec<u8>, String> {
        use argon2::{Algorithm, Params, Version};

        let mut key = vec![0u8; 32]; // 256-bit key
        let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, Params::default());

        argon2
            .hash_password_into(password.as_bytes(), salt.as_bytes(), &mut key)
            .map_err(|e| format!("Failed to derive key: {}", e))?;

        Ok(key)
    }

    fn encrypt_data(data: &[u8], key: &[u8]) -> Result<Vec<u8>, String> {
        let cipher =
            Aes256Gcm::new_from_slice(key).map_err(|e| format!("Failed to create cipher: {}", e))?;

        let mut nonce_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        let mut ciphertext = cipher
            .encrypt(nonce, data)
            .map_err(|e| format!("Encryption failed: {}", e))?;

        let mut result = nonce_bytes.to_vec();
        result.append(&mut ciphertext);

        Ok(result)
    }

    fn decrypt_data(data: &[u8], key: &[u8]) -> Result<Vec<u8>, String> {
        if data.len() < 12 {
            return Err("Invalid encrypted data".to_string());
        }

        let (nonce_bytes, ciphertext) = data.split_at(12);
        let nonce = Nonce::from_slice(nonce_bytes);

        let cipher =
            Aes256Gcm::new_from_slice(key).map_err(|e| format!("Failed to create cipher: {}", e))?;

        cipher
            .decrypt(nonce, ciphertext)
            .map_err(|_| "Decryption failed - wrong password or corrupted data".to_string())
    }
}
