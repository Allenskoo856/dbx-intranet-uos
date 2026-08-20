// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if std::env::args().any(|arg| arg == "--dbx-offline-self-test") {
        let mode = if cfg!(feature = "offline-uos") { "offline-uos" } else { "standard" };
        let updater = if cfg!(feature = "offline-uos") { "disabled" } else { "enabled" };
        println!(
            "dbx_offline_self_test mode={mode} network_policy={} updater={updater} agent_remote_downloads={} mcp_registry_checks={}",
            if cfg!(feature = "offline-uos") { "deny-public" } else { "standard" },
            if cfg!(feature = "offline-uos") { "disabled" } else { "enabled" },
            if cfg!(feature = "offline-uos") { "disabled" } else { "enabled" },
        );
        return;
    }

    dbx_lib::run();
}
