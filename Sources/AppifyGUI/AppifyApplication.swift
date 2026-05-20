import Cocoa

/// Custom NSApplication subclass that stops any active modal session
/// before proceeding with termination.
///
/// Both `runSetupUI` (via `NSApp.runModal(for:)`) and `NSAlert.runModal()`
/// enter a modal event loop.  Vanilla `NSApplication.terminate:` *queues*
/// the termination request when a modal loop is active and does **not**
/// process it until the modal session ends – meaning the user cannot
/// quit without first dismissing the dialog.
///
/// This override calls `stopModal` + closes the modal window to tear
/// down the modal session, then terminates the process immediately.
@objc(AppifyApplication)
class AppifyApplication: NSApplication {

    override func terminate(_ sender: Any?) {
        // Stop any active modal sessions.  This is necessary because
        // the standard terminate: implementation defers the request
        // when a modal session is active, effectively ignoring it.
        //
        // note: we use a single if (not while) because stopModal() just
        // sets a flag – the loop won't actually exit until the current
        // event iteration finishes.  Since exit(0) follows immediately,
        // the process will be gone before the loop could recheck anyway.
        if modalWindow != nil {
            stopModal()
            // close the modal window so it doesn't linger on screen
            modalWindow?.close()
        }

        // We use exit(0) instead of super.terminate: to guarantee the
        // app terminates even if a modal session hasn't fully unwound
        // yet (the modal loop checks the stop flag on the *next* event
        // loop iteration, but we want to quit *now*).
        exit(0)
    }
}
