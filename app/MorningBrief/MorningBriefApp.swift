import SwiftUI

@main
struct MorningBriefApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(model)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)

        // SwiftUI opens this window at launch; AppDelegate closes it again once setup is done.
        Window("Morning Brief Setup", id: "setup") {
            SetupView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }

    private var menuIcon: String {
        if model.brief.status == "error" { return "exclamationmark.circle" }
        return model.brief.today.contains { $0.priority == "high" } ? "checklist.unchecked" : "checklist"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let model = AppModel.shared
            if model.needsSetup {
                NSApp.activate(ignoringOtherApps: true)
            } else {
                // Already set up: live quietly in the menu bar.
                NSApp.windows.filter { $0.title == "Morning Brief Setup" }.forEach { $0.close() }
                model.startSchedule()
            }
        }
    }
}
