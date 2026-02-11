use tauri::Emitter;
use tauri_plugin_global_shortcut::GlobalShortcutExt;

/// Register a global keyboard shortcut that emits an event to the frontend.
#[tauri::command]
pub fn register_shortcut(
    app: tauri::AppHandle,
    shortcut: String,
    action: String,
) -> Result<(), String> {
    let action_clone = action.clone();
    let handle = app.clone();

    app.global_shortcut()
        .on_shortcut(shortcut.as_str(), move |_app, _shortcut, _event| {
            let _ = handle.emit(&format!("shortcut:{}", action_clone), ());
        })
        .map_err(|e| e.to_string())
}

/// Unregister a global keyboard shortcut.
#[tauri::command]
pub fn unregister_shortcut(app: tauri::AppHandle, shortcut: String) -> Result<(), String> {
    app.global_shortcut()
        .unregister(shortcut.as_str())
        .map_err(|e| e.to_string())
}
