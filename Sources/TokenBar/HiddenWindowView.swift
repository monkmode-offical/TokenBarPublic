import AppKit
import SwiftUI

struct HiddenWindowView: View {
    @Bindable var settings: SettingsStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .background(KeepaliveWindowAccessor { window in
                self.configureKeepaliveWindow(window)
            })
            .onReceive(NotificationCenter.default.publisher(for: .tokenbarOpenSettings)) { _ in
                Task { @MainActor in
                    self.openSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tokenbarOpenDashboard)) { _ in
                Task { @MainActor in
                    self.openWindow(id: AppDashboardView.windowID)
                }
            }
            .task {
                #if DEBUG
                // Migration is only useful for local debug rebuild loops; running it in release can trigger
                // unnecessary keychain prompts for end users on first launch.
                await Task.detached(priority: .userInitiated) {
                    KeychainMigration.migrateIfNeeded()
                }.value
                #endif
                await self.settings.verifyStoredLicenseIfNeeded(force: false)
            }
    }

    @MainActor
    private func configureKeepaliveWindow(_ window: NSWindow) {
        // Keep the helper scene alive for openSettings/openWindow actions, but never visible to users.
        window.styleMask = [.borderless]
        window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
        window.isExcludedFromWindowsMenu = true
        window.level = .floating
        window.isOpaque = false
        window.alphaValue = 0
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.setContentSize(NSSize(width: 1, height: 1))
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderOut(nil)
    }
}

private struct KeepaliveWindowAccessor: NSViewRepresentable {
    let onWindowResolved: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            self.onWindowResolved(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            self.onWindowResolved(window)
        }
    }
}
