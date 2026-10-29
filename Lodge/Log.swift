import os

extension Logger {
    /// Everything Lodge logs uses this subsystem (Help ▸ Report a Bug… collects it).
    static let subsystem = "com.sebastianphillips.Lodge"

    /// Card mounts and the "Import with Lodge?" prompt. Read with
    /// `/usr/bin/log show --last 10m --info --debug --predicate 'subsystem == "com.sebastianphillips.Lodge"'`
    /// (in zsh, plain `log` is a shell builtin).
    static let importPrompt = Logger(subsystem: subsystem, category: "ImportPrompt")

    /// Launches and crash reports.
    static let app = Logger(subsystem: subsystem, category: "App")
}
