mod keychain;
mod notifications;
mod shortcuts;
mod tray;
mod updater;

use tauri::{Emitter, Listener};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            tray::setup_tray(app.handle())?;

            // Listen for deep link events
            let handle = app.handle().clone();
            app.listen("deep-link://new-url", move |event: tauri::Event| {
                let payload = event.payload();
                let _ = handle.emit("deep-link", payload);
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            keychain::keychain_store,
            keychain::keychain_load,
            keychain::keychain_delete,
            notifications::send_notification,
            shortcuts::register_shortcut,
            shortcuts::unregister_shortcut,
            updater::check_for_update,
        ])
        .run(tauri::generate_context!())
        .expect("error running Murmuring desktop");
}
