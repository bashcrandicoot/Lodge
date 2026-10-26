import os

extension Logger {
    /// Card mounts and the "Import with Lodge?" prompt. Read with
    /// `/usr/bin/log show --last 10m --info --debug --predicate 'subsystem == "com.sebastianphillips.Lodge"'`
    /// (in zsh, plain `log` is a shell builtin).
    static let importPrompt = Logger(subsystem: "com.sebastianphillips.Lodge", category: "ImportPrompt")
}
