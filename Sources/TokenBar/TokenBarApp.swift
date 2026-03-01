import AppKit
import KeyboardShortcuts
import Observation
import QuartzCore
import Security
import SwiftUI
import TokenBarCore

@main
struct TokenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var store: UsageStore
    private let preferencesSelection: PreferencesSelection
    private let account: AccountInfo

    init() {
        let env = ProcessInfo.processInfo.environment
        let storedLevel = TokenBarLog.parseLevel(UserDefaults.standard.string(forKey: "debugLogLevel")) ?? .verbose
        let level = TokenBarLog.parseLevel(env["TOKENBAR_LOG_LEVEL"]) ?? storedLevel
        TokenBarLog.bootstrapIfNeeded(.init(
            destination: .oslog(subsystem: "com.tokenbar"),
            level: level,
            json: false))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let gitCommit = Bundle.main.object(forInfoDictionaryKey: "TokenGitCommit") as? String ?? "unknown"
        let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "TokenBuildTimestamp") as? String ?? "unknown"
        TokenBarLog.logger(LogCategories.app).info(
            "TokenBar starting",
            metadata: [
                "version": version,
                "build": build,
                "git": gitCommit,
                "built": buildTimestamp,
            ])

        KeychainAccessGate.isDisabled = UserDefaults.standard.bool(forKey: "debugDisableKeychainAccess")
        KeychainPromptCoordinator.install()

        let preferencesSelection = PreferencesSelection()
        let settings = SettingsStore()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let account = fetcher.loadAccountInfo()
        let store = UsageStore(fetcher: fetcher, browserDetection: browserDetection, settings: settings)
        self.preferencesSelection = preferencesSelection
        _settings = State(wrappedValue: settings)
        _store = State(wrappedValue: store)
        self.account = account
        TokenBarLog.setLogLevel(settings.debugLogLevel)
        self.appDelegate.configure(
            store: store,
            settings: settings,
            account: account,
            selection: preferencesSelection)
    }

    @SceneBuilder
    var body: some Scene {
        // Hidden 1×1 helper scene to keep SwiftUI's lifecycle alive so `Settings` scene
        // shows the native toolbar tabs even though the UI is AppKit-based.
        WindowGroup(" ") {
            HiddenWindowView(settings: self.settings)
        }
        .defaultSize(width: 1, height: 1)
        .windowStyle(.hiddenTitleBar)

        Window("TokenBar", id: AppDashboardView.windowID) {
            AppDashboardView(
                settings: self.settings,
                store: self.store,
                account: self.account)
        }
        .defaultSize(width: 980, height: 740)

        Settings {
            PreferencesView(
                settings: self.settings,
                store: self.store,
                updater: self.appDelegate.updaterController,
                selection: self.preferencesSelection)
        }
        .defaultSize(width: PreferencesTab.general.preferredWidth, height: PreferencesTab.general.preferredHeight)
        .windowResizability(.contentSize)
    }

    private func openSettings(tab: PreferencesTab) {
        self.preferencesSelection.tab = tab
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

// MARK: - Updater abstraction

@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    var updateStatus: UpdateStatus { get }
    func checkForUpdates(_ sender: Any?)
    func installUpdateNow()
}

/// No-op updater used for debug builds and non-bundled runs to suppress Sparkle dialogs.
final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    let isAvailable: Bool = false
    let unavailableReason: String?
    let updateStatus = UpdateStatus()

    init(unavailableReason: String? = nil) {
        self.unavailableReason = unavailableReason
    }

    func checkForUpdates(_ sender: Any?) {}
    func installUpdateNow() {}
}

@MainActor
@Observable
final class UpdateStatus {
    static let disabled = UpdateStatus()
    var isUpdateReady: Bool

    init(isUpdateReady: Bool = false) {
        self.isUpdateReady = isUpdateReady
    }
}

#if canImport(Sparkle) && ENABLE_SPARKLE
@preconcurrency import Sparkle

@MainActor
final class SparkleUpdaterController: NSObject, UpdaterProviding, SPUUpdaterDelegate {
    private final class ImmediateInstallHandlerBox: @unchecked Sendable {
        let handler: () -> Void

        init(handler: @escaping () -> Void) {
            self.handler = handler
        }
    }

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil)
    let updateStatus = UpdateStatus()
    let unavailableReason: String? = nil
    private var immediateInstallHandler: (() -> Void)?

    init(savedAutoUpdate: Bool) {
        super.init()
        let updater = self.controller.updater
        updater.automaticallyChecksForUpdates = savedAutoUpdate
        updater.automaticallyDownloadsUpdates = savedAutoUpdate
        self.controller.startUpdater()
        if savedAutoUpdate {
            DispatchQueue.main.async { [weak self] in
                self?.controller.updater.checkForUpdatesInBackground()
            }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { self.controller.updater.automaticallyChecksForUpdates }
        set { self.controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { self.controller.updater.automaticallyDownloadsUpdates }
        set { self.controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    var isAvailable: Bool {
        true
    }

    func checkForUpdates(_ sender: Any?) {
        self.controller.checkForUpdates(sender)
    }

    func installUpdateNow() {
        if let immediateInstallHandler = self.immediateInstallHandler {
            self.immediateInstallHandler = nil
            self.updateStatus.isUpdateReady = false
            immediateInstallHandler()
            return
        }

        // Fallback for cases where Sparkle didn't give us an immediate-install callback yet.
        self.controller.checkForUpdates(nil)
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateStatus.isUpdateReady = true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateStatus.isUpdateReady = true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        Task { @MainActor in
            self.immediateInstallHandler = nil
            self.updateStatus.isUpdateReady = false
        }
    }

    nonisolated func userDidCancelDownload(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.immediateInstallHandler = nil
            self.updateStatus.isUpdateReady = false
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void)
        -> Bool
    {
        let handlerBox = ImmediateInstallHandlerBox(handler: immediateInstallHandler)
        Task { @MainActor in
            self.immediateInstallHandler = handlerBox.handler
            self.updateStatus.isUpdateReady = true
        }
        return true
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState)
    {
        let downloaded = state.stage == .downloaded
        Task { @MainActor in
            switch choice {
            case .install, .skip:
                self.immediateInstallHandler = nil
                self.updateStatus.isUpdateReady = false
            case .dismiss:
                self.updateStatus.isUpdateReady = downloaded
            @unknown default:
                self.immediateInstallHandler = nil
                self.updateStatus.isUpdateReady = false
            }
        }
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateChannel.current.allowedSparkleChannels
    }
}

private func isDeveloperIDSigned(bundleURL: URL) -> Bool {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
          let code = staticCode else { return false }

    var infoCF: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
          let info = infoCF as? [String: Any],
          let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let leaf = certs.first else { return false }

    if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
        return summary.hasPrefix("Developer ID Application:")
    }
    return false
}

@MainActor
private func makeUpdaterController() -> UpdaterProviding {
    let bundleURL = Bundle.main.bundleURL
    let isBundledApp = bundleURL.pathExtension == "app"
    guard isBundledApp else {
        return DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
    }

    if InstallOrigin.isHomebrewCask(appBundleURL: bundleURL) {
        return DisabledUpdaterController(
            unavailableReason: "Updates managed by Homebrew. Run: brew upgrade --cask tokenbar/tap/tokenbar")
    }

    guard isDeveloperIDSigned(bundleURL: bundleURL) else {
        return DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
    }

    let defaults = UserDefaults.standard
    let autoUpdateKey = "autoUpdateEnabled"
    // Default to true for first launch; fall back to saved preference thereafter.
    let savedAutoUpdate = (defaults.object(forKey: autoUpdateKey) as? Bool) ?? true
    return SparkleUpdaterController(savedAutoUpdate: savedAutoUpdate)
}
#else
private func makeUpdaterController() -> UpdaterProviding {
    DisabledUpdaterController()
}
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hasShownInitialDashboardKey = "hasShownInitialDashboard"
    let updaterController: UpdaterProviding = makeUpdaterController()
    private var statusController: StatusItemControlling?
    private var store: UsageStore?
    private var settings: SettingsStore?
    private var account: AccountInfo?
    private var preferencesSelection: PreferencesSelection?

    func configure(store: UsageStore, settings: SettingsStore, account: AccountInfo, selection: PreferencesSelection) {
        self.store = store
        self.settings = settings
        self.account = account
        self.preferencesSelection = selection
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        self.configureAppIconForMacOSVersion()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppNotifications.shared.requestAuthorizationOnStartup()
        if let settings {
            let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
            _ = NSApp.setActivationPolicy(policy)
        }
        self.ensureStatusController()
        self.openDashboardOnFirstLaunchIfNeeded()
        KeyboardShortcuts.onKeyUp(for: .openMenu) { [weak self] in
            Task { @MainActor [weak self] in
                self?.statusController?.openMenuFromShortcut()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            self.handleDeepLink(url: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard self.settings?.showDockIcon == true else { return false }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .tokenbarOpenDashboard,
            object: nil,
            userInfo: nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TTYCommandRunner.terminateActiveProcessesForAppShutdown()
    }

    private func handleDeepLink(url: URL) {
        guard url.scheme?.lowercased() == "tokenbar" else { return }

        let route = self.deepLinkRoute(url)
        guard self.isLicenseActivationRoute(route) else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let licenseKey = self.queryValue(
            in: components,
            keys: ["license_key", "licenseKey", "key"])

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.preferencesSelection?.tab = .general
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(
                name: .tokenbarOpenSettings,
                object: nil,
                userInfo: ["tab": PreferencesTab.general.rawValue])

            guard let licenseKey,
                  !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                self.settings?.licenseStatusMessage = "Activation link missing license key."
                return
            }

            await self.settings?.activateLicenseKey(licenseKey)
        }
    }

    private func deepLinkRoute(_ url: URL) -> [String] {
        var parts: [String] = []
        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !host.isEmpty
        {
            parts.append(host)
        }
        parts.append(contentsOf: url.pathComponents.compactMap { component in
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.isEmpty || trimmed == "/" {
                return nil
            }
            return trimmed
        })
        return parts
    }

    private func isLicenseActivationRoute(_ route: [String]) -> Bool {
        if route == ["license"] { return true }
        if route == ["activate"] { return true }
        if route == ["license", "activate"] { return true }
        return false
    }

    private func queryValue(in components: URLComponents?, keys: [String]) -> String? {
        guard let queryItems = components?.queryItems, !queryItems.isEmpty else { return nil }

        let lowercasedKeys = Set(keys.map { $0.lowercased() })
        for item in queryItems {
            guard lowercasedKeys.contains(item.name.lowercased()),
                  let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                continue
            }
            return value
        }
        return nil
    }

    /// Use the classic (non-Liquid Glass) app icon on macOS versions before 26.
    private func configureAppIconForMacOSVersion() {
        if #unavailable(macOS 26) {
            self.applyClassicAppIcon()
        }
    }

    private func applyClassicAppIcon() {
        guard let classicIcon = Self.loadClassicIcon() else { return }
        NSApp.applicationIconImage = classicIcon
    }

    private static func loadClassicIcon() -> NSImage? {
        guard let url = self.classicIconURL(),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        return image
    }

    private static func classicIconURL() -> URL? {
        Bundle.main.url(forResource: "Icon-classic", withExtension: "icns")
    }

    private func ensureStatusController() {
        if self.statusController != nil { return }

        if let store, let settings, let account, let selection = self.preferencesSelection {
            self.statusController = StatusItemController.factory(
                store,
                settings,
                account,
                self.updaterController,
                selection)
            return
        }

        // Defensive fallback: this should not be hit in normal app lifecycle.
        TokenBarLog.logger(LogCategories.app)
            .error("StatusItemController fallback path used; settings/store mismatch likely.")
        assertionFailure("StatusItemController fallback path used; check app lifecycle wiring.")
        let fallbackSettings = SettingsStore()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let fallbackAccount = fetcher.loadAccountInfo()
        let fallbackStore = UsageStore(fetcher: fetcher, browserDetection: browserDetection, settings: fallbackSettings)
        self.statusController = StatusItemController.factory(
            fallbackStore,
            fallbackSettings,
            fallbackAccount,
            self.updaterController,
            PreferencesSelection())
    }

    private func openDashboardOnFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: self.hasShownInitialDashboardKey) {
            return
        }

        defaults.set(true, forKey: self.hasShownInitialDashboardKey)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .tokenbarOpenDashboard,
            object: nil,
            userInfo: nil)
    }
}
