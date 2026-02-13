use tauri_plugin_notification::NotificationExt;

/// Send a privacy-respecting OS notification.
/// Content never includes message text — only channel name.
#[tauri::command]
pub fn send_notification(
    app: tauri::AppHandle,
    title: String,
    body: String,
) -> Result<(), String> {
    app.notification()
        .builder()
        .title(&title)
        .body(&body)
        .show()
        .map_err(|e| e.to_string())
}
