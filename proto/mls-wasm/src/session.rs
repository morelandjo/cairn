use std::cell::RefCell;
use std::collections::HashMap;

use openmls::prelude::*;
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;

pub struct Session {
    pub provider: OpenMlsRustCrypto,
    pub signer: SignatureKeyPair,
    pub credential_with_key: CredentialWithKey,
    #[allow(dead_code)]
    pub identity: Vec<u8>,
}

thread_local! {
    static SESSIONS: RefCell<HashMap<u32, Session>> = RefCell::new(HashMap::new());
    static NEXT_ID: RefCell<u32> = const { RefCell::new(1) };
}

pub fn new_session(
    identity: Vec<u8>,
    signer: SignatureKeyPair,
    credential_with_key: CredentialWithKey,
) -> Result<u32, String> {
    let id = NEXT_ID.with(|cell| {
        let mut next = cell.borrow_mut();
        let id = *next;
        *next += 1;
        id
    });

    let provider = OpenMlsRustCrypto::default();
    signer
        .store(provider.storage())
        .map_err(|e| format!("failed to store signer: {:?}", e))?;

    SESSIONS.with(|cell| {
        cell.borrow_mut().insert(
            id,
            Session {
                provider,
                signer,
                credential_with_key,
                identity,
            },
        );
    });

    Ok(id)
}

pub fn drop_session(id: u32) -> bool {
    SESSIONS.with(|cell| cell.borrow_mut().remove(&id).is_some())
}

pub fn with_session<F, R>(id: u32, f: F) -> Result<R, String>
where
    F: FnOnce(&mut Session) -> Result<R, String>,
{
    SESSIONS.with(|cell| {
        let mut sessions = cell.borrow_mut();
        match sessions.get_mut(&id) {
            Some(session) => f(session),
            None => Err(format!("session {} not found", id)),
        }
    })
}
