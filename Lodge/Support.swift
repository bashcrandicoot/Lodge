import SwiftUI
import AppKit

/// Who makes Lodge and how to reach them. Change the email here and it changes everywhere:
/// the About window, Help ▸ Contact Support… / Report a Bug… and the Settings footer.
enum Support {
    static let developerName = "bashframes"
    static let email = "bashframes@gmail.com"
    /// Buy Lodge (Lodge ▸ Buy Lodge…, Help ▸ Buy Lodge…, the Settings footer and the buy note).
    static var buyURL: URL { LodgeLicense.buyURL }

    /// A plain `mailto:` link, for the About window and the Settings footer.
    static var emailURL: URL { mailURL(body: nil) }

    /// A new email with the subject "Lodge Support" and, under a blank line for the message,
    /// the Lodge and macOS versions (so we know what to look at).
    static var supportEmailURL: URL { mailURL(body: "\n\n—\n\(versionSummary)") }

    static func mailURL(subject: String = "Lodge Support", body: String?) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let body { components.queryItems?.append(URLQueryItem(name: "body", value: body)) }
        return components.url ?? URL(string: "mailto:\(email)")!
    }

    /// "Lodge <version> (<build>), macOS <x.y.z>"
    static var versionSummary: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Lodge \(version) (\(build)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// The small print under the icon in the About window: the support link.
    static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(string: "Made by \(developerName)\nSupport: ", attributes: base)
        var link = base
        link[.link] = emailURL
        credits.append(NSAttributedString(string: email, attributes: link))
        credits.append(NSAttributedString(string: "\n", attributes: base))
        var buy = base
        buy[.link] = buyURL
        credits.append(NSAttributedString(string: "Buy Lodge", attributes: buy))
        if let notices = acknowledgements {
            credits.append(NSAttributedString(string: "\n\nAcknowledgements\n\n", attributes: base))
            var small = base
            small[.font] = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1)
            let left = NSMutableParagraphStyle()
            left.alignment = .left
            small[.paragraphStyle] = left
            credits.append(NSAttributedString(string: notices, attributes: small))
        }
        return credits
    }

    /// Open source notices (Sparkle's MIT license), bundled as Acknowledgements.txt.
    static var acknowledgements: String? {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutCredits])
    }

    static func contactSupport() {
        NSWorkspace.shared.open(supportEmailURL)
    }

    /// Opens the Polar checkout in the browser.
    static func openBuyPage() {
        NSWorkspace.shared.open(buyURL)
    }
}

/// The quiet "Made by bashframes · Support" line at the bottom of Settings ▸ General.
struct SettingsCreditsFooter: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Made by \(Support.developerName)")
            Text("·").accessibilityHidden(true)
            Link("Support", destination: Support.supportEmailURL)
                .help("Email \(Support.email)")
            Text("·").accessibilityHidden(true)
            Button("Report a Bug…") { BugReport.compose() }
                .buttonStyle(.link)
                .help("Email a bug report with Lodge’s recent log attached")
            Text("·").accessibilityHidden(true)
            Link("Buy Lodge", destination: Support.buyURL)
                .help("Lodge is $10, one time")
                .accessibilityLabel("Buy Lodge")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
