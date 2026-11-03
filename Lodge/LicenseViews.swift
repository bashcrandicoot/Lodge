import SwiftUI

extension LicenseModel {
    var keyDraftBinding: Binding<String> {
        Binding(get: { self.keyDraft }, set: { self.keyDraft = $0 })
    }
}

/// Key entry shown from the trial toolbar. Buying and activating both stay available.
struct LicenseEntrySheet: View {
    @EnvironmentObject private var license: LicenseModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LicenseCopy.enterLicenseKey)
                .font(.headline)
            Text(LicenseCopy.price)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(LicenseCopy.keyPrompt, text: license.keyDraftBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await submit() } }
            HStack {
                Button(LicenseCopy.buy) { openURL(LodgeLicense.buyURL) }
                Spacer()
                Button(LicenseCopy.activate) { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(license.isWorking || LicenseKey.normalize(license.keyDraft).isEmpty)
            }
            if let banner = license.banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func submit() async {
        await license.activate()
        if license.allowsUse, license.trialDaysLeft == nil { dismiss() }
    }
}

/// Shown in place of the funnel until this Mac has a usable license.
struct LicenseGate: View {
    @EnvironmentObject private var license: LicenseModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            licenseForm
                .padding(24)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeBackground())
    }

    private var licenseForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LicenseCopy.price)
                .fixedSize(horizontal: false, vertical: true)
            Text(license.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if license.canDeactivate {
                if let masked = license.maskedKey {
                    Text(masked)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                Button(LicenseCopy.checkAgain) { Task { await license.refresh() } }
                    .disabled(license.isWorking)
                Button(LicenseCopy.deactivate) { Task { await license.deactivate() } }
                    .disabled(license.isWorking)
            } else {
                Text(LicenseCopy.enterLicenseKey)
                TextField(LicenseCopy.keyPrompt, text: license.keyDraftBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await license.activate() } }
                Button(LicenseCopy.activate) { Task { await license.activate() } }
                    .disabled(license.isWorking || LicenseKey.normalize(license.keyDraft).isEmpty)
            }
            Button(LicenseCopy.buy) { openURL(LodgeLicense.buyURL) }
                .buttonStyle(.themeProminent)
                .disabled(license.isWorking)
            licenseNotes
        }
    }

    @ViewBuilder private var licenseNotes: some View {
        if license.isWorking {
            Text(LicenseCopy.checking)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let banner = license.banner {
            Text(banner)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings ▸ General ▸ License, including Deactivate for this Mac.
struct LicenseSettingsSection: View {
    @EnvironmentObject private var license: LicenseModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Text(LicenseCopy.price)
                .fixedSize(horizontal: false, vertical: true)
            if license.canDeactivate {
                if let masked = license.maskedKey {
                    LabeledContent(LicenseCopy.thisMac, value: masked)
                }
                Button(LicenseCopy.deactivate) { Task { await license.deactivate() } }
                    .disabled(license.isWorking)
                if license.needsCheck {
                    Button(LicenseCopy.checkAgain) { Task { await license.refresh() } }
                        .disabled(license.isWorking)
                }
            } else {
                TextField(LicenseCopy.keyPrompt, text: license.keyDraftBinding)
                    .onSubmit { Task { await license.activate() } }
                Button(LicenseCopy.activate) { Task { await license.activate() } }
                    .disabled(license.isWorking || LicenseKey.normalize(license.keyDraft).isEmpty)
            }
            Button(LicenseCopy.buy) { openURL(LodgeLicense.buyURL) }
                .disabled(license.isWorking)
            if license.isWorking {
                Text(LicenseCopy.checking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let banner = license.banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(LicenseCopy.section)
        } footer: {
            Text(license.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await license.refresh() }
    }
}
