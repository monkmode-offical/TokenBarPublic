import AppKit
import SwiftUI

@MainActor
struct AboutPane: View {
    let updater: UpdaterProviding
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @AppStorage(UpdateChannel.userDefaultsKey)
    private var updateChannelRaw: String = UpdateChannel.defaultChannel.rawValue
    @State private var didLoadUpdaterState = false
    private static let logoResourceName = "BrandLogo"

    private static var topLogoImage: NSImage? {
        if let url = Bundle.main.url(forResource: Self.logoResourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TokenBuildTimestamp") as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let image = Self.topLogoImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(spacing: 2) {
                Text("TokenBar")
                    .font(.title3).bold()
                Text("Version \(self.versionString)")
                    .foregroundStyle(.secondary)
                if let buildTimestamp {
                    Text("Built \(buildTimestamp)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Offline-first. Usage tracking, timeline, and session analytics stay on your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .center, spacing: 10) {
                AboutLinkRow(
                    icon: "chevron.left.slash.chevron.right",
                    title: "GitHub",
                    url: "https://github.com/tokenbar/tokenbar")
                AboutLinkRow(icon: "globe", title: "Website", url: "https://tokenbar.app")
                AboutLinkRow(icon: "envelope", title: "Contact", url: "mailto:hello@tokenbar.app")
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Divider()

            if self.updater.isAvailable {
                VStack(spacing: 10) {
                    Toggle("Check for updates automatically", isOn: self.$autoUpdateEnabled)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .center)
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Update Channel")
                            Spacer()
                            Picker("", selection: self.updateChannelBinding) {
                                ForEach(UpdateChannel.allCases) { channel in
                                    Text(channel.displayName).tag(channel)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .frame(maxWidth: 280)
                        Text(self.updateChannel.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }
                    Button("Check for Updates…") { self.updater.checkForUpdates(nil) }
                }
            } else {
                Text(self.updater.unavailableReason ?? "Updates unavailable in this build.")
                    .foregroundStyle(.secondary)
            }

            Text("© 2026 TokenBar Team.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear {
            guard !self.didLoadUpdaterState else { return }
            // Align Sparkle's flag with the persisted preference on first load.
            self.updater.automaticallyChecksForUpdates = self.autoUpdateEnabled
            self.updater.automaticallyDownloadsUpdates = self.autoUpdateEnabled
            self.didLoadUpdaterState = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            self.updater.automaticallyChecksForUpdates = newValue
            self.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    private var updateChannel: UpdateChannel {
        UpdateChannel(rawValue: self.updateChannelRaw) ?? .stable
    }

    private var updateChannelBinding: Binding<UpdateChannel> {
        Binding(
            get: { self.updateChannel },
            set: { newValue in
                self.updateChannelRaw = newValue.rawValue
                self.updater.checkForUpdates(nil)
            })
    }

}
