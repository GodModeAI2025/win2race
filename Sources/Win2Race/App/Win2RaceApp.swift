import AppKit
import SwiftUI

@main
struct Win2RaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Win-to-Race", id: "main") {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.bootstrap()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neue Aufgabe") {
                    store.showSimpleComposer()
                }
                .keyboardShortcut("n")
            }

            CommandMenu("Win-to-Race") {
                Button("Runs anzeigen") {
                    store.showDashboard()
                }
                .keyboardShortcut("r")

                Button("CLI-Setup aktualisieren") {
                    store.refreshSetupState()
                }
                .keyboardShortcut("u")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 680, height: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
