mod error;
mod session;

use openmls::prelude::*;
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use tls_codec::Deserialize as TlsDeserializeTrait;
use tls_codec::Serialize as TlsSerializeTrait;
use wasm_bindgen::prelude::*;

use error::to_js_error;

const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

// ==================== Smoke / Info ====================

#[wasm_bindgen]
pub fn mls_version() -> String {
    "RFC9420-v1".to_string()
}

#[wasm_bindgen]
pub fn supported_ciphersuites() -> String {
    serde_json::json!([
        {
            "name": "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
            "value": 1
        }
    ])
    .to_string()
}

// ==================== Credential Bundle ====================

#[wasm_bindgen]
pub struct WasmCredentialBundle {
    identity: Vec<u8>,
    signing_public_key: Vec<u8>,
    signing_private_key: Vec<u8>,
}

#[wasm_bindgen]
impl WasmCredentialBundle {
    #[wasm_bindgen(getter)]
    pub fn identity(&self) -> Vec<u8> {
        self.identity.clone()
    }

    #[wasm_bindgen(getter, js_name = "signingPublicKey")]
    pub fn signing_public_key(&self) -> Vec<u8> {
        self.signing_public_key.clone()
    }

    #[wasm_bindgen(getter, js_name = "signingPrivateKey")]
    pub fn signing_private_key(&self) -> Vec<u8> {
        self.signing_private_key.clone()
    }
}

#[wasm_bindgen]
pub fn create_credential(identity_public_key: &[u8]) -> Result<WasmCredentialBundle, JsError> {
    if identity_public_key.len() != 32 {
        return Err(JsError::new("identity public key must be 32 bytes"));
    }

    let keys = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm()).map_err(to_js_error)?;

    let kp_value = serde_json::to_value(&keys)
        .map_err(|e| JsError::new(&format!("serialize keypair: {}", e)))?;
    let private_bytes: Vec<u8> = serde_json::from_value(
        kp_value
            .get("private")
            .ok_or_else(|| JsError::new("missing private key in serialized keypair"))?
            .clone(),
    )
    .map_err(|e| JsError::new(&format!("extract private key: {}", e)))?;

    Ok(WasmCredentialBundle {
        identity: identity_public_key.to_vec(),
        signing_public_key: keys.public().to_vec(),
        signing_private_key: private_bytes,
    })
}

#[wasm_bindgen]
pub fn import_signing_key(
    identity_public_key: &[u8],
    signing_private_key: &[u8],
    signing_public_key: &[u8],
) -> Result<WasmCredentialBundle, JsError> {
    if identity_public_key.len() != 32 {
        return Err(JsError::new("identity public key must be 32 bytes"));
    }
    if signing_public_key.len() != 32 {
        return Err(JsError::new("signing public key must be 32 bytes"));
    }

    let private_key = normalize_signing_key(signing_private_key)?;
    let _keys = SignatureKeyPair::from_raw(
        CIPHERSUITE.signature_algorithm(),
        private_key.clone(),
        signing_public_key.to_vec(),
    );

    Ok(WasmCredentialBundle {
        identity: identity_public_key.to_vec(),
        signing_public_key: signing_public_key.to_vec(),
        signing_private_key: private_key,
    })
}

// ==================== KeyPackage Generation (Standalone) ====================

#[wasm_bindgen]
pub struct WasmKeyPackageResult {
    key_package_data: Vec<u8>,
    init_private_key: Vec<u8>,
}

#[wasm_bindgen]
impl WasmKeyPackageResult {
    #[wasm_bindgen(getter, js_name = "keyPackageData")]
    pub fn key_package_data(&self) -> Vec<u8> {
        self.key_package_data.clone()
    }

    #[wasm_bindgen(getter, js_name = "initPrivateKey")]
    pub fn init_private_key(&self) -> Vec<u8> {
        self.init_private_key.clone()
    }
}

fn normalize_signing_key(signing_private_key: &[u8]) -> Result<Vec<u8>, JsError> {
    match signing_private_key.len() {
        32 => Ok(signing_private_key.to_vec()),
        64 => Ok(signing_private_key[..32].to_vec()),
        n => Err(JsError::new(&format!(
            "signing private key must be 32 or 64 bytes, got {}",
            n
        ))),
    }
}

#[wasm_bindgen]
pub fn generate_key_package(
    identity: &[u8],
    signing_private_key: &[u8],
    signing_public_key: &[u8],
) -> Result<WasmKeyPackageResult, JsError> {
    if identity.len() != 32 {
        return Err(JsError::new("identity must be 32 bytes"));
    }
    if signing_public_key.len() != 32 {
        return Err(JsError::new("signing public key must be 32 bytes"));
    }

    let private_key = normalize_signing_key(signing_private_key)?;
    let provider = OpenMlsRustCrypto::default();

    let signer = SignatureKeyPair::from_raw(
        CIPHERSUITE.signature_algorithm(),
        private_key,
        signing_public_key.to_vec(),
    );
    signer
        .store(provider.storage())
        .map_err(|_| JsError::new("failed to store signer"))?;

    let credential = BasicCredential::new(identity.to_vec());
    let credential_with_key = CredentialWithKey {
        credential: credential.into(),
        signature_key: SignaturePublicKey::from(signing_public_key.to_vec()),
    };

    let bundle = KeyPackage::builder()
        .build(CIPHERSUITE, &provider, &signer, credential_with_key)
        .map_err(to_js_error)?;

    let kp_bytes = bundle
        .key_package()
        .tls_serialize_detached()
        .map_err(to_js_error)?;

    let init_key_value = serde_json::to_value(bundle.init_private_key())
        .map_err(|e| JsError::new(&format!("serialize init key: {}", e)))?;
    let init_key_bytes: Vec<u8> = serde_json::from_value(
        init_key_value
            .get("vec")
            .ok_or_else(|| JsError::new("missing vec in init key"))?
            .clone(),
    )
    .map_err(|e| JsError::new(&format!("extract init key bytes: {}", e)))?;

    Ok(WasmKeyPackageResult {
        key_package_data: kp_bytes,
        init_private_key: init_key_bytes,
    })
}

// ==================== Session Management ====================

fn build_signer_and_credential(
    identity: &[u8],
    signing_private_key: &[u8],
    signing_public_key: &[u8],
) -> Result<(SignatureKeyPair, CredentialWithKey), JsError> {
    if identity.len() != 32 {
        return Err(JsError::new("identity must be 32 bytes"));
    }
    if signing_public_key.len() != 32 {
        return Err(JsError::new("signing public key must be 32 bytes"));
    }

    let private_key = normalize_signing_key(signing_private_key)?;
    let signer = SignatureKeyPair::from_raw(
        CIPHERSUITE.signature_algorithm(),
        private_key,
        signing_public_key.to_vec(),
    );

    let credential = BasicCredential::new(identity.to_vec());
    let credential_with_key = CredentialWithKey {
        credential: credential.into(),
        signature_key: SignaturePublicKey::from(signing_public_key.to_vec()),
    };

    Ok((signer, credential_with_key))
}

#[wasm_bindgen]
pub fn create_session(
    identity: &[u8],
    signing_private_key: &[u8],
    signing_public_key: &[u8],
) -> Result<u32, JsError> {
    let (signer, credential_with_key) =
        build_signer_and_credential(identity, signing_private_key, signing_public_key)?;
    session::new_session(identity.to_vec(), signer, credential_with_key)
        .map_err(|e| JsError::new(&e))
}

#[wasm_bindgen]
pub fn destroy_session(session_id: u32) -> bool {
    session::drop_session(session_id)
}

#[wasm_bindgen]
pub fn session_generate_key_package(session_id: u32) -> Result<WasmKeyPackageResult, JsError> {
    session::with_session(session_id, |s| {
        let bundle = KeyPackage::builder()
            .build(
                CIPHERSUITE,
                &s.provider,
                &s.signer,
                s.credential_with_key.clone(),
            )
            .map_err(|e| format!("{:?}", e))?;

        let kp_bytes = bundle
            .key_package()
            .tls_serialize_detached()
            .map_err(|e| format!("{:?}", e))?;

        let init_key_value = serde_json::to_value(bundle.init_private_key())
            .map_err(|e| format!("serialize init key: {}", e))?;
        let init_key_bytes: Vec<u8> = serde_json::from_value(
            init_key_value
                .get("vec")
                .ok_or_else(|| "missing vec in init key".to_string())?
                .clone(),
        )
        .map_err(|e| format!("extract init key: {}", e))?;

        Ok(WasmKeyPackageResult {
            key_package_data: kp_bytes,
            init_private_key: init_key_bytes,
        })
    })
    .map_err(|e| JsError::new(&e))
}

// ==================== Group Operations ====================

#[wasm_bindgen]
pub struct WasmAddMemberResult {
    commit: Vec<u8>,
    welcome: Vec<u8>,
}

#[wasm_bindgen]
impl WasmAddMemberResult {
    #[wasm_bindgen(getter)]
    pub fn commit(&self) -> Vec<u8> {
        self.commit.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn welcome(&self) -> Vec<u8> {
        self.welcome.clone()
    }
}

#[wasm_bindgen]
pub struct WasmProcessedMessage {
    message_type: String,
    plaintext: Vec<u8>,
    sender_identity: Vec<u8>,
}

#[wasm_bindgen]
impl WasmProcessedMessage {
    #[wasm_bindgen(getter, js_name = "messageType")]
    pub fn message_type(&self) -> String {
        self.message_type.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn plaintext(&self) -> Vec<u8> {
        self.plaintext.clone()
    }

    #[wasm_bindgen(getter, js_name = "senderIdentity")]
    pub fn sender_identity(&self) -> Vec<u8> {
        self.sender_identity.clone()
    }
}

fn load_group(s: &session::Session, group_id: &[u8]) -> Result<MlsGroup, String> {
    let gid = GroupId::from_slice(group_id);
    MlsGroup::load(s.provider.storage(), &gid)
        .map_err(|e| format!("load group: {:?}", e))?
        .ok_or_else(|| "group not found in session".to_string())
}

fn extract_identity(credential: &Credential) -> Vec<u8> {
    match BasicCredential::try_from(credential.clone()) {
        Ok(basic) => basic.identity().to_vec(),
        Err(_) => vec![],
    }
}

#[wasm_bindgen]
pub fn create_mls_group(session_id: u32, group_id: &[u8]) -> Result<(), JsError> {
    session::with_session(session_id, |s| {
        let _group = MlsGroup::builder()
            .with_group_id(GroupId::from_slice(group_id))
            .ciphersuite(CIPHERSUITE)
            .use_ratchet_tree_extension(true)
            .build(&s.provider, &s.signer, s.credential_with_key.clone())
            .map_err(|e| format!("create group: {:?}", e))?;
        Ok(())
    })
    .map_err(|e| JsError::new(&e))
}

#[wasm_bindgen]
pub fn add_member(
    session_id: u32,
    group_id: &[u8],
    key_package_tls: &[u8],
) -> Result<WasmAddMemberResult, JsError> {
    session::with_session(session_id, |s| {
        let mut group = load_group(s, group_id)?;

        // Deserialize and validate the KeyPackage
        let kp_in = KeyPackageIn::tls_deserialize(&mut &key_package_tls[..])
            .map_err(|e| format!("deserialize key package: {:?}", e))?;
        let kp = kp_in
            .validate(s.provider.crypto(), ProtocolVersion::Mls10)
            .map_err(|e| format!("validate key package: {:?}", e))?;

        // Add member (returns commit + welcome)
        let (commit_out, welcome_out, _group_info) = group
            .add_members(&s.provider, &s.signer, &[kp])
            .map_err(|e| format!("add member: {:?}", e))?;

        // Merge the pending commit on the adder's side
        group
            .merge_pending_commit(&s.provider)
            .map_err(|e| format!("merge pending commit: {:?}", e))?;

        // Serialize outputs
        let commit_bytes = commit_out
            .tls_serialize_detached()
            .map_err(|e| format!("serialize commit: {:?}", e))?;
        let welcome_bytes = welcome_out
            .tls_serialize_detached()
            .map_err(|e| format!("serialize welcome: {:?}", e))?;

        Ok(WasmAddMemberResult {
            commit: commit_bytes,
            welcome: welcome_bytes,
        })
    })
    .map_err(|e| JsError::new(&e))
}

#[wasm_bindgen]
pub fn remove_member(
    session_id: u32,
    group_id: &[u8],
    leaf_index: u32,
) -> Result<Vec<u8>, JsError> {
    session::with_session(session_id, |s| {
        let mut group = load_group(s, group_id)?;

        let (commit_out, _welcome, _group_info) = group
            .remove_members(&s.provider, &s.signer, &[LeafNodeIndex::new(leaf_index)])
            .map_err(|e| format!("remove member: {:?}", e))?;

        group
            .merge_pending_commit(&s.provider)
            .map_err(|e| format!("merge pending commit: {:?}", e))?;

        commit_out
            .tls_serialize_detached()
            .map_err(|e| format!("serialize commit: {:?}", e))
    })
    .map_err(|e| JsError::new(&e))
}

#[wasm_bindgen]
pub fn process_welcome(session_id: u32, welcome_tls: &[u8]) -> Result<Vec<u8>, JsError> {
    session::with_session(session_id, |s| {
        let mls_msg_in = MlsMessageIn::tls_deserialize(&mut &welcome_tls[..])
            .map_err(|e| format!("deserialize welcome: {:?}", e))?;

        let welcome = match mls_msg_in.extract() {
            MlsMessageBodyIn::Welcome(w) => w,
            _ => return Err("expected Welcome message".to_string()),
        };

        let join_config = MlsGroupJoinConfig::builder()
            .use_ratchet_tree_extension(true)
            .build();

        let staged = StagedWelcome::new_from_welcome(&s.provider, &join_config, welcome, None)
            .map_err(|e| format!("stage welcome: {:?}", e))?;

        let group_id = staged.group_context().group_id().as_slice().to_vec();

        let _group = staged
            .into_group(&s.provider)
            .map_err(|e| format!("finalize welcome: {:?}", e))?;

        Ok(group_id)
    })
    .map_err(|e| JsError::new(&e))
}

#[wasm_bindgen]
pub fn encrypt_message(
    session_id: u32,
    group_id: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, JsError> {
    session::with_session(session_id, |s| {
        let mut group = load_group(s, group_id)?;

        let msg_out = group
            .create_message(&s.provider, &s.signer, plaintext)
            .map_err(|e| format!("encrypt: {:?}", e))?;

        msg_out
            .tls_serialize_detached()
            .map_err(|e| format!("serialize: {:?}", e))
    })
    .map_err(|e| JsError::new(&e))
}

#[wasm_bindgen]
pub fn process_group_message(
    session_id: u32,
    group_id: &[u8],
    message_tls: &[u8],
) -> Result<WasmProcessedMessage, JsError> {
    session::with_session(session_id, |s| {
        let mut group = load_group(s, group_id)?;

        let mls_msg_in = MlsMessageIn::tls_deserialize(&mut &message_tls[..])
            .map_err(|e| format!("deserialize message: {:?}", e))?;

        // Extract the protocol message from the MLS envelope
        let body = mls_msg_in.extract();
        let processed = match body {
            MlsMessageBodyIn::PublicMessage(m) => group
                .process_message(&s.provider, m)
                .map_err(|e| format!("process message: {:?}", e))?,
            MlsMessageBodyIn::PrivateMessage(m) => group
                .process_message(&s.provider, m)
                .map_err(|e| format!("process message: {:?}", e))?,
            _ => return Err("expected PublicMessage or PrivateMessage".to_string()),
        };

        let sender_identity = extract_identity(processed.credential());

        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(app_msg) => Ok(WasmProcessedMessage {
                message_type: "application".to_string(),
                plaintext: app_msg.into_bytes(),
                sender_identity,
            }),
            ProcessedMessageContent::StagedCommitMessage(staged_commit) => {
                group
                    .merge_staged_commit(&s.provider, *staged_commit)
                    .map_err(|e| format!("merge commit: {:?}", e))?;
                Ok(WasmProcessedMessage {
                    message_type: "commit".to_string(),
                    plaintext: vec![],
                    sender_identity,
                })
            }
            ProcessedMessageContent::ProposalMessage(_proposal) => Ok(WasmProcessedMessage {
                message_type: "proposal".to_string(),
                plaintext: vec![],
                sender_identity,
            }),
            ProcessedMessageContent::ExternalJoinProposalMessage(_) => Ok(WasmProcessedMessage {
                message_type: "external_proposal".to_string(),
                plaintext: vec![],
                sender_identity,
            }),
        }
    })
    .map_err(|e| JsError::new(&e))
}

// ==================== Group Inspection ====================

#[wasm_bindgen]
pub fn get_epoch(session_id: u32, group_id: &[u8]) -> Result<u64, JsError> {
    session::with_session(session_id, |s| {
        let group = load_group(s, group_id)?;
        Ok(group.epoch().as_u64())
    })
    .map_err(|e| JsError::new(&e))
}

#[wasm_bindgen]
pub fn get_members(session_id: u32, group_id: &[u8]) -> Result<String, JsError> {
    session::with_session(session_id, |s| {
        let group = load_group(s, group_id)?;
        let members: Vec<serde_json::Value> = group
            .members()
            .map(|m| {
                let identity = extract_identity(&m.credential);
                serde_json::json!({
                    "index": m.index.u32(),
                    "identity": identity,
                    "signature_key": m.signature_key,
                })
            })
            .collect();
        serde_json::to_string(&members).map_err(|e| format!("serialize members: {}", e))
    })
    .map_err(|e| JsError::new(&e))
}
