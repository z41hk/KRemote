use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum Protocol {
    Ssh,
    Rdp,
    Vnc,
    Http,
    Https,
    Vpn,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Connection {
    pub id: String,
    pub name: String,
    pub protocol: Protocol,
    pub host: String,
    pub port: u16,
    pub username: Option<String>,
    pub password: Option<String>,
    pub private_key_path: Option<String>,
    pub folder_id: Option<String>,
    pub tags: Vec<String>,
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Folder {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
}

impl Connection {
    pub fn new(name: String, protocol: Protocol, host: String, port: u16) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            protocol,
            host,
            port,
            username: None,
            password: None,
            private_key_path: None,
            folder_id: None,
            tags: Vec::new(),
            notes: None,
        }
    }
}

impl Folder {
    pub fn new(name: String, parent_id: Option<String>) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            parent_id,
        }
    }
}
