import AppKit
import TactKit

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let controller = AppController()
    application.delegate = controller
    withExtendedLifetime(controller) {
        application.run()
    }
}
