/// OS keychain integration for secure key storage.
///
/// - macOS: Keychain Services via security-framework
/// - Linux: Secret Service D-Bus API via secret-service
/// - Windows: Credential Manager via windows crate

const SERVICE_NAME: &str = "dev.cairn.desktop";

#[tauri::command]
pub fn keychain_store(key: String, value: String) -> Result<(), String> {
    platform::store(SERVICE_NAME, &key, &value)
}

#[tauri::command]
pub fn keychain_load(key: String) -> Result<Option<String>, String> {
    platform::load(SERVICE_NAME, &key)
}

#[tauri::command]
pub fn keychain_delete(key: String) -> Result<(), String> {
    platform::delete(SERVICE_NAME, &key)
}

#[cfg(target_os = "macos")]
mod platform {
    use security_framework::passwords::{
        delete_generic_password, get_generic_password, set_generic_password,
    };

    pub fn store(service: &str, key: &str, value: &str) -> Result<(), String> {
        set_generic_password(service, key, value.as_bytes()).map_err(|e| e.to_string())
    }

    pub fn load(service: &str, key: &str) -> Result<Option<String>, String> {
        match get_generic_password(service, key) {
            Ok(bytes) => {
                let s = String::from_utf8(bytes.to_vec()).map_err(|e| e.to_string())?;
                Ok(Some(s))
            }
            Err(e) if e.code() == -25300 => Ok(None), // errSecItemNotFound
            Err(e) => Err(e.to_string()),
        }
    }

    pub fn delete(service: &str, key: &str) -> Result<(), String> {
        match delete_generic_password(service, key) {
            Ok(()) => Ok(()),
            Err(e) if e.code() == -25300 => Ok(()), // already gone
            Err(e) => Err(e.to_string()),
        }
    }
}

#[cfg(target_os = "linux")]
mod platform {
    use secret_service::blocking::SecretService;
    use secret_service::EncryptionType;

    pub fn store(service: &str, key: &str, value: &str) -> Result<(), String> {
        let ss = SecretService::connect(EncryptionType::Dh).map_err(|e| e.to_string())?;
        let collection = ss.get_default_collection().map_err(|e| e.to_string())?;
        collection
            .create_item(
                &format!("{service}:{key}"),
                vec![("service", service), ("key", key)].into_iter().collect(),
                value.as_bytes(),
                true, // replace
                "text/plain",
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn load(service: &str, key: &str) -> Result<Option<String>, String> {
        let ss = SecretService::connect(EncryptionType::Dh).map_err(|e| e.to_string())?;
        let collection = ss.get_default_collection().map_err(|e| e.to_string())?;
        let items = collection
            .search_items(vec![("service", service), ("key", key)].into_iter().collect())
            .map_err(|e| e.to_string())?;
        match items.first() {
            Some(item) => {
                let secret = item.get_secret().map_err(|e| e.to_string())?;
                let s = String::from_utf8(secret).map_err(|e| e.to_string())?;
                Ok(Some(s))
            }
            None => Ok(None),
        }
    }

    pub fn delete(service: &str, key: &str) -> Result<(), String> {
        let ss = SecretService::connect(EncryptionType::Dh).map_err(|e| e.to_string())?;
        let collection = ss.get_default_collection().map_err(|e| e.to_string())?;
        let items = collection
            .search_items(vec![("service", service), ("key", key)].into_iter().collect())
            .map_err(|e| e.to_string())?;
        for item in items {
            item.delete().map_err(|e| e.to_string())?;
        }
        Ok(())
    }
}

#[cfg(target_os = "windows")]
mod platform {
    pub fn store(_service: &str, _key: &str, _value: &str) -> Result<(), String> {
        // Windows Credential Manager integration via windows crate
        // TODO: Implement with PasswordVault API
        Err("Windows keychain not yet implemented".into())
    }

    pub fn load(_service: &str, _key: &str) -> Result<Option<String>, String> {
        Err("Windows keychain not yet implemented".into())
    }

    pub fn delete(_service: &str, _key: &str) -> Result<(), String> {
        Err("Windows keychain not yet implemented".into())
    }
}

// Fallback for other platforms (e.g., compile checks)
#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
mod platform {
    pub fn store(_service: &str, _key: &str, _value: &str) -> Result<(), String> {
        Err("Keychain not supported on this platform".into())
    }

    pub fn load(_service: &str, _key: &str) -> Result<Option<String>, String> {
        Err("Keychain not supported on this platform".into())
    }

    pub fn delete(_service: &str, _key: &str) -> Result<(), String> {
        Err("Keychain not supported on this platform".into())
    }
}
