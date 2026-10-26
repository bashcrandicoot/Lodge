import AppKit

/// The confirmations for "Re-offload Everything" and "Forget This Card's History".
/// The wording is pure (and tested); `make…` builds the NSAlert.
enum ReoffloadAlert {
    /// "Forget History" is the second button; Cancel is first and the default.
    static let forgetResponse = NSApplication.ModalResponse.alertSecondButtonReturn

    static func everythingText(cardName: String, fileCount: Int) -> (title: String, message: String) {
        let files = fileCount == 1 ? "The 1 file" : "All \(fileCount) files"
        return ("Re-offload everything on “\(cardName)”?",
                "\(files) will be copied and verified again as new copies, including ones already offloaded. "
                + "Existing copies are never overwritten: the usual naming rules apply, so new copies get the "
                + "next sequence number, or “_2” at the end of the name.")
    }

    static func forgetText(cardName: String, entryCount: Int) -> (title: String, message: String) {
        let what = entryCount == 1 ? "the 1 file" : "the \(entryCount) files"
        return ("Forget the offload history of “\(cardName)”?",
                "SnapDrop will forget \(what) it offloaded from this card, so they show as new and are copied "
                + "again next time. The copies already at the destination aren’t touched.\n\n"
                + "Until this card is offloaded again, it won’t be ready to format.")
    }

    static func makeEverything(cardName: String, fileCount: Int) -> NSAlert {
        let (title, message) = everythingText(cardName: cardName, fileCount: fileCount)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Re-offload Everything")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func makeForget(cardName: String, entryCount: Int) -> NSAlert {
        let (title, message) = forgetText(cardName: cardName, entryCount: entryCount)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        let forget = alert.addButton(withTitle: "Forget History")
        forget.keyEquivalent = ""
        forget.hasDestructiveAction = true
        return alert
    }
}
