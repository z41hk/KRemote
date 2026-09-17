use roxmltree::Document;
use std::collections::HashMap;

use super::models::{Connection, Folder, Protocol};

/// Parse a mRemoteNG XML file and extract connections and folders.
/// Returns (connections, folders).
pub fn parse_mremoteng_xml(xml_content: &str) -> Result<(Vec<Connection>, Vec<Folder>), String> {
    let doc =
        Document::parse(xml_content).map_err(|e| format!("Failed to parse XML: {}", e))?;

    let mut connections = Vec::new();
    let mut folders = Vec::new();
    let mut folder_map: HashMap<String, String> = HashMap::new(); // XML ID -> new UUID

    // mRemoteNG stores everything under <mrng:Connections> as <Node> elements.
    // Nodes with Type="Connection" are connections, Type="Container" are folders.
    let root = doc.root_element();
    
    // Find the Connections element (namespace may vary)
    let connections_node = root
        .descendants()
        .find(|n| n.tag_name().name() == "Connections")
        .ok_or("No Connections element found in XML")?;

    // Recursively traverse all Node elements
    parse_nodes(&connections_node, None, &mut connections, &mut folders, &mut folder_map)?;

    Ok((connections, folders))
}

fn parse_nodes(
    parent: &roxmltree::Node,
    parent_folder_id: Option<String>,
    connections: &mut Vec<Connection>,
    folders: &mut Vec<Folder>,
    folder_map: &mut HashMap<String, String>,
) -> Result<(), String> {
    for node in parent.children().filter(|n| n.is_element() && n.tag_name().name() == "Node") {
        let node_type = node.attribute("Type").unwrap_or("Connection");
        let name = node.attribute("Name").unwrap_or("Unnamed").to_string();

        if node_type == "Container" {
            // It's a folder
            let folder_id = uuid::Uuid::new_v4().to_string();
            let folder = Folder {
                id: folder_id.clone(),
                name: name.clone(),
                parent_id: parent_folder_id.clone(),
            };
            folders.push(folder);

            // Store mapping from XML node (by name, since mRemoteNG doesn't always have stable IDs) to our UUID
            folder_map.insert(name.clone(), folder_id.clone());

            // Recurse into children
            parse_nodes(&node, Some(folder_id), connections, folders, folder_map)?;
        } else {
            // It's a connection
            let protocol_str = node.attribute("Protocol").unwrap_or("SSH").to_uppercase();
            let protocol = match protocol_str.as_str() {
                "SSH1" | "SSH2" | "SSH" => Protocol::Ssh,
                "RDP" => Protocol::Rdp,
                "VNC" => Protocol::Vnc,
                "HTTP" => Protocol::Http,
                "HTTPS" => Protocol::Https,
                _ => Protocol::Ssh, // default fallback
            };

            let host = node.attribute("Hostname").unwrap_or("").to_string();
            let port_str = node.attribute("Port").unwrap_or("22");
            let port = port_str.parse::<u16>().unwrap_or(22);

            let username = node.attribute("Username").and_then(|u| {
                if u.is_empty() {
                    None
                } else {
                    Some(u.to_string())
                }
            });

            let password = node.attribute("Password").and_then(|p| {
                if p.is_empty() {
                    None
                } else {
                    // mRemoteNG stores passwords encrypted, but for import we'll assume
                    // the user has exported them in plaintext or we skip them.
                    // A real implementation would need to decrypt mRemoteNG's encryption.
                    Some(p.to_string())
                }
            });

            let description = node.attribute("Description").and_then(|d| {
                if d.is_empty() {
                    None
                } else {
                    Some(d.to_string())
                }
            });

            let connection = Connection {
                id: uuid::Uuid::new_v4().to_string(),
                name,
                protocol,
                host,
                port,
                username,
                password,
                private_key_path: None,
                folder_id: parent_folder_id.clone(),
                tags: Vec::new(),
                notes: description,
                jump_host_id: None,
            };

            connections.push(connection);
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_simple_mremoteng() {
        let xml = r#"<?xml version="1.0" encoding="utf-8"?>
<mrng:Connections xmlns:mrng="http://mremoteng.org" Name="Connections">
    <Node Name="Server1" Type="Connection" Protocol="SSH" Hostname="192.168.1.10" Port="22" Username="admin" />
    <Node Name="Folder1" Type="Container">
        <Node Name="Server2" Type="Connection" Protocol="RDP" Hostname="192.168.1.20" Port="3389" Username="user" />
    </Node>
</mrng:Connections>"#;

        let (connections, folders) = parse_mremoteng_xml(xml).unwrap();

        assert_eq!(connections.len(), 2);
        assert_eq!(folders.len(), 1);

        assert_eq!(connections[0].name, "Server1");
        assert_eq!(connections[0].protocol, Protocol::Ssh);
        assert_eq!(connections[0].host, "192.168.1.10");

        assert_eq!(folders[0].name, "Folder1");

        assert_eq!(connections[1].name, "Server2");
        assert_eq!(connections[1].protocol, Protocol::Rdp);
        assert!(connections[1].folder_id.is_some());
    }
}
