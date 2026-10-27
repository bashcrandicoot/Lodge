import SwiftUI
import AppKit

/// Who makes Lodge and how to reach them. Change the email here and it changes everywhere:
/// the About window, Help ▸ Contact Support… and the Settings footer.
enum Support {
    static let developerName = "bashframes"
    static let email = "bashframes@gmail.com"
    /// Tips for Lodge (Help ▸ Support Lodge…, the Settings footer and the support card).
    static let tipJarURL = URL(string: "https://bashframes.gumroad.com/l/lodge")!

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

    /// "Lodge 1.0.0 (1), macOS 15.1.0"
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
        return credits
    }

    static func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutCredits])
    }

    static func contactSupport() {
        NSWorkspace.shared.open(supportEmailURL)
    }

    /// Opens the Gumroad page in the browser.
    static func openTipJar() {
        NSWorkspace.shared.open(tipJarURL)
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
            Link("Support Lodge ♥", destination: Support.tipJarURL)
                .help("Leave a tip for Lodge on Gumroad")
                .accessibilityLabel("Support Lodge")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
