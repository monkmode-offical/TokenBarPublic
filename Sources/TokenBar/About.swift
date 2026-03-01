import AppKit

@MainActor
func showAbout() {
    NSApp.activate(ignoringOtherApps: true)

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let versionString = build.isEmpty ? version : "\(version) (\(build))"
    let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "TokenBuildTimestamp") as? String
    let gitCommit = Bundle.main.object(forInfoDictionaryKey: "TokenGitCommit") as? String

    let separator = NSAttributedString(string: " · ", attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
    ])

    func makeLink(_ title: String, urlString: String) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .link: URL(string: urlString) as Any,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
    }

    let credits = NSMutableAttributedString(string: "TokenBar Team\n")
    credits.append(makeLink("GitHub", urlString: "https://github.com/tokenbar/tokenbar"))
    credits.append(separator)
    credits.append(makeLink("Website", urlString: "https://tokenbar.app"))
    credits.append(separator)
    credits.append(makeLink("Contact", urlString: "mailto:hello@tokenbar.app"))
    if let buildTimestamp, let formatted = formattedBuildTimestamp(buildTimestamp) {
        var builtLine = "Built \(formatted)"
        if let gitCommit, !gitCommit.isEmpty, gitCommit != "unknown" {
            builtLine += " (\(gitCommit)"
            #if DEBUG
            builtLine += " DEBUG BUILD"
            #endif
            builtLine += ")"
        }
        credits.append(NSAttributedString(string: "\n\(builtLine)", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
    }

    let options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationName: "TokenBar",
        .applicationVersion: versionString,
        .version: versionString,
        .credits: credits,
        .applicationIcon: aboutPanelLogoImage() as Any,
    ]

    NSApp.orderFrontStandardAboutPanel(options: options)

    // Remove the focus ring around the app icon in the standard About panel for a cleaner look.
    if let aboutPanel = NSApp.windows.first(where: { $0.className.contains("About") }) {
        removeFocusRings(in: aboutPanel.contentView)
    }
}

@MainActor
private func aboutPanelLogoImage() -> NSImage {
    if let url = Bundle.main.url(forResource: "BrandLogo", withExtension: "png"),
       let image = NSImage(contentsOf: url)
    {
        return image
    }
    return NSApplication.shared.applicationIconImage ?? NSImage()
}

private func formattedBuildTimestamp(_ timestamp: String) -> String? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime]
    guard let date = parser.date(from: timestamp) else { return timestamp }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = .current
    return formatter.string(from: date)
}

@MainActor
private func removeFocusRings(in view: NSView?) {
    guard let view else { return }
    if let imageView = view as? NSImageView {
        imageView.focusRingType = .none
    }
    for subview in view.subviews {
        removeFocusRings(in: subview)
    }
}
