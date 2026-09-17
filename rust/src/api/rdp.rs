// RDP (Remote Desktop Protocol) client implementation using IronRDP
// This module provides RDP connection capabilities for KRemote

use crate::api::models::Connection;
use std::io::Write as _;
use std::net::TcpStream;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ironrdp::connector::{self, ClientConnector, ConnectionResult, Credentials};
use ironrdp::pdu::gcc::KeyboardType;
use ironrdp::pdu::rdp::capability_sets::MajorPlatformType;
use ironrdp::pdu::rdp::client_info::{CompressionType, PerformanceFlags, TimezoneInfo};
use ironrdp::session::image::DecodedImage;
use ironrdp::session::ActiveStageBuilder;
use rustls::pki_types;
use tokio_rustls::rustls;

type UpgradedFramed = ironrdp_blocking::Framed<rustls::StreamOwned<rustls::ClientConnection, TcpStream>>;

/// Test RDP connection with credentials
pub fn test_rdp_connection(
    host: String,
    port: u16,
    username: String,
    password: String,
    domain: Option<String>,
) -> Result<String, String> {
    // Build connector configuration
    let config = build_rdp_config(username, password, domain, 1280, 1024)
        .map_err(|e| format!("Failed to build RDP config: {}", e))?;

    // Attempt connection
    let server_addr = format!("{}:{}", host, port);
    let result = std::panic::catch_unwind(|| {
        connect_rdp(config, host.clone(), port)
    });

    match result {
        Ok(Ok(_)) => Ok(format!("Successfully connected to RDP server at {}", server_addr)),
        Ok(Err(e)) => Err(format!("RDP connection failed: {}", e)),
        Err(_) => Err("RDP connection panicked".to_string()),
    }
}

/// RDP connection state manager
#[flutter_rust_bridge::frb(opaque)]
pub struct RdpConnection {
    connection_info: Option<Connection>,
    state: Arc<Mutex<RdpState>>,
}

struct RdpState {
    framed: Option<UpgradedFramed>,
    active_stage: Option<ironrdp::session::ActiveStage>,
    image: DecodedImage,
    width: u16,
    height: u16,
    connected: bool,
}

impl RdpConnection {
    pub fn new() -> Self {
        Self {
            connection_info: None,
            state: Arc::new(Mutex::new(RdpState {
                framed: None,
                active_stage: None,
                image: DecodedImage::new(
                    ironrdp::graphics::image_processing::PixelFormat::RgbA32,
                    1280,
                    1024,
                ),
                width: 1280,
                height: 1024,
                connected: false,
            })),
        }
    }

    pub fn connect(&mut self, connection: &Connection) -> Result<(), String> {
        // Store connection info
        self.connection_info = Some(connection.clone());

        let username = connection.username.clone().unwrap_or_default();
        let password = connection.password.clone().unwrap_or_default();
        let domain = connection.domain.clone();

        // Build connector config
        let config = build_rdp_config(username, password, domain, 1280, 1024)
            .map_err(|e| format!("Failed to build RDP config: {}", e))?;

        // Connect
        let (connection_result, framed) = connect_rdp(config, connection.host.clone(), connection.port)
            .map_err(|e| format!("Connection failed: {}", e))?;

        // Build active stage
        let active_stage = ActiveStageBuilder {
            static_channels: connection_result.static_channels,
            user_channel_id: connection_result.user_channel_id,
            io_channel_id: connection_result.io_channel_id,
            message_channel_id: connection_result.message_channel_id,
            share_id: connection_result.share_id,
            compression_type: connection_result.compression_type,
            enable_server_pointer: connection_result.enable_server_pointer,
            pointer_software_rendering: connection_result.pointer_software_rendering,
        }
        .build();

        // Update state
        let mut state = self.state.lock().map_err(|e| format!("Lock error: {}", e))?;
        state.framed = Some(framed);
        state.active_stage = Some(active_stage);
        state.width = connection_result.desktop_size.width;
        state.height = connection_result.desktop_size.height;
        state.image = DecodedImage::new(
            ironrdp::graphics::image_processing::PixelFormat::RgbA32,
            connection_result.desktop_size.width,
            connection_result.desktop_size.height,
        );
        state.connected = true;

        Ok(())
    }

    pub fn disconnect(&mut self) -> Result<(), String> {
        let mut state = self.state.lock().map_err(|e| format!("Lock error: {}", e))?;
        state.framed = None;
        state.active_stage = None;
        state.connected = false;
        Ok(())
    }

    pub fn is_connected(&self) -> bool {
        self.state.lock().map(|s| s.connected).unwrap_or(false)
    }

    pub fn get_framebuffer(&self) -> Result<Vec<u8>, String> {
        let state = self.state.lock().map_err(|e| format!("Lock error: {}", e))?;
        Ok(state.image.data().to_vec())
    }

    pub fn get_size(&self) -> (u16, u16) {
        self.state.lock().map(|s| (s.width, s.height)).unwrap_or((1280, 1024))
    }
}

// Helper functions

fn build_rdp_config(
    username: String,
    password: String,
    domain: Option<String>,
    width: u16,
    height: u16,
) -> anyhow::Result<connector::Config> {
    Ok(connector::Config {
        credentials: Credentials::UsernamePassword { username, password },
        domain,
        enable_tls: true,
        enable_credssp: true,
        keyboard_type: KeyboardType::IbmEnhanced,
        keyboard_subtype: 0,
        keyboard_layout: 0,
        keyboard_functional_keys_count: 12,
        ime_file_name: String::new(),
        dig_product_id: String::new(),
        desktop_size: connector::DesktopSize { width, height },
        bitmap: None,
        client_build: 0,
        client_name: "KRemote".to_owned(),
        client_dir: "C:\\Windows\\System32\\mstscax.dll".to_owned(),

        #[cfg(windows)]
        platform: MajorPlatformType::WINDOWS,
        #[cfg(target_os = "linux")]
        platform: MajorPlatformType::UNIX,
        #[cfg(target_os = "macos")]
        platform: MajorPlatformType::MACINTOSH,

        enable_server_pointer: true,
        request_data: None,
        autologon: true,
        enable_audio_playback: false,
        compression_type: Some(CompressionType::Rdp61),
        pointer_software_rendering: true,
        multitransport_flags: None,
        performance_flags: PerformanceFlags::default(),
        desktop_scale_factor: 0,
        hardware_id: None,
        license_cache: None,
        timezone_info: TimezoneInfo::default(),
        alternate_shell: String::new(),
        work_dir: String::new(),
    })
}

fn connect_rdp(
    config: connector::Config,
    server_name: String,
    port: u16,
) -> anyhow::Result<(ConnectionResult, UpgradedFramed)> {
    use std::net::ToSocketAddrs as _;

    // Resolve server address
    let server_addr = (server_name.as_str(), port)
        .to_socket_addrs()?
        .next()
        .ok_or_else(|| anyhow::anyhow!("Could not resolve server address"))?;

    // Connect via TCP
    let tcp_stream = TcpStream::connect_timeout(&server_addr, Duration::from_secs(10))?;
    tcp_stream.set_read_timeout(Some(Duration::from_secs(30)))?;

    let client_addr = tcp_stream.local_addr()?;

    let mut framed = ironrdp_blocking::Framed::new(tcp_stream);
    let mut connector = ClientConnector::new(config, client_addr);

    // Begin connection sequence
    let should_upgrade = ironrdp_blocking::connect_begin(&mut framed, &mut connector)?;

    // TLS upgrade
    let initial_stream = framed.into_inner_no_leftover();
    let (upgraded_stream, server_public_key) = tls_upgrade(initial_stream, server_name.clone())?;

    let upgraded = ironrdp_blocking::mark_as_upgraded(should_upgrade, &mut connector);
    let mut upgraded_framed = ironrdp_blocking::Framed::new(upgraded_stream);

    // Finalize connection with CredSSP/NLA
    let mut network_client = sspi::network_client::reqwest_network_client::ReqwestNetworkClient;
    let connection_result = ironrdp_blocking::connect_finalize(
        upgraded,
        connector,
        &mut upgraded_framed,
        &mut network_client,
        server_name.into(),
        server_public_key,
        None,
    )?;

    Ok((connection_result, upgraded_framed))
}

fn tls_upgrade(
    stream: TcpStream,
    server_name: String,
) -> anyhow::Result<(rustls::StreamOwned<rustls::ClientConnection, TcpStream>, Vec<u8>)> {
    let mut config = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(std::sync::Arc::new(danger::NoCertificateVerification))
        .with_no_client_auth();

    // Disable TLS resumption (not supported by CredSSP)
    config.resumption = rustls::client::Resumption::disabled();

    let config = std::sync::Arc::new(config);
    let server_name = pki_types::ServerName::try_from(server_name)?;
    let client = rustls::ClientConnection::new(config, server_name)?;

    let mut tls_stream = rustls::StreamOwned::new(client, stream);
    tls_stream.flush()?;

    // Extract server certificate public key
    let cert = tls_stream
        .conn
        .peer_certificates()
        .and_then(|certs| certs.first())
        .ok_or_else(|| anyhow::anyhow!("No peer certificate"))?;

    let server_public_key = extract_tls_server_public_key(cert.as_ref())?;

    Ok((tls_stream, server_public_key))
}

fn extract_tls_server_public_key(cert: &[u8]) -> anyhow::Result<Vec<u8>> {
    use x509_cert::der::Decode as _;

    let cert = x509_cert::Certificate::from_der(cert)?;
    let server_public_key = cert
        .tbs_certificate
        .subject_public_key_info
        .subject_public_key
        .as_bytes()
        .ok_or_else(|| anyhow::anyhow!("Subject public key not aligned"))?
        .to_owned();

    Ok(server_public_key)
}

mod danger {
    use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
    use rustls::{DigitallySignedStruct, Error, SignatureScheme, pki_types};

    #[derive(Debug)]
    pub(super) struct NoCertificateVerification;

    impl ServerCertVerifier for NoCertificateVerification {
        fn verify_server_cert(
            &self,
            _: &pki_types::CertificateDer<'_>,
            _: &[pki_types::CertificateDer<'_>],
            _: &pki_types::ServerName<'_>,
            _: &[u8],
            _: pki_types::UnixTime,
        ) -> Result<ServerCertVerified, Error> {
            Ok(ServerCertVerified::assertion())
        }

        fn verify_tls12_signature(
            &self,
            _: &[u8],
            _: &pki_types::CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn verify_tls13_signature(
            &self,
            _: &[u8],
            _: &pki_types::CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
            vec![
                SignatureScheme::RSA_PKCS1_SHA1,
                SignatureScheme::ECDSA_SHA1_Legacy,
                SignatureScheme::RSA_PKCS1_SHA256,
                SignatureScheme::ECDSA_NISTP256_SHA256,
                SignatureScheme::RSA_PKCS1_SHA384,
                SignatureScheme::ECDSA_NISTP384_SHA384,
                SignatureScheme::RSA_PKCS1_SHA512,
                SignatureScheme::ECDSA_NISTP521_SHA512,
                SignatureScheme::RSA_PSS_SHA256,
                SignatureScheme::RSA_PSS_SHA384,
                SignatureScheme::RSA_PSS_SHA512,
                SignatureScheme::ED25519,
                SignatureScheme::ED448,
            ]
        }
    }
}
