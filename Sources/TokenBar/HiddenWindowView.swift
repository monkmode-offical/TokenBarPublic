import AppKit
import SwiftUI

struct HiddenWindowView: View {
    @Bindable var settings: SettingsStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var configuredKeepaliveWindowID: ObjectIdentifier?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .background(KeepaliveWindowAccessor { window in
                let windowID = ObjectIdentifier(window)
                guard self.configuredKeepaliveWindowID != windowID else { return }
                self.configureKeepaliveWindow(window)
                self.configuredKeepaliveWindowID = windowID
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
        // Avoid mutating style mask/content size for SwiftUI-managed windows while AppKit is laying out.
        window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
        window.isExcludedFromWindowsMenu = true
        window.level = .floating
        window.isOpaque = false
        window.alphaValue = 0
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.orderOut(nil)
    }
}

private struct KeepaliveWindowAccessor: NSViewRepresentable {
    final class Coordinator {
        weak var resolvedWindow: NSWindow?
    }

    let onWindowResolved: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        self.resolveWindow(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        self.resolveWindow(for: nsView, coordinator: context.coordinator)
    }

    private func resolveWindow(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator, let window = view.window else { return }
            guard coordinator.resolvedWindow !== window else { return }
            coordinator.resolvedWindow = window
            self.onWindowResolved(window)
        }
    }
}
