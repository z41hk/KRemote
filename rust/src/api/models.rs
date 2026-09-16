use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
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
    pub folder: Option<String>,
    pub tags: Vec<String>,
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionFolder {
    pub name: String,
    pub parent: Option<String>,
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
            folder: None,
            tags: Vec::new(),
            notes: None,
        }
    }
}
