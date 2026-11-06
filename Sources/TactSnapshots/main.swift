import AppKit
import TactKit

// Development tool. Usage: TactSnapshots screens <folder> | TactSnapshots icon <folder>
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: TactSnapshots screens|icon <folder>")
    exit(1)
}

let folder = URL(fileURLWithPath: arguments[2])
MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    do {
        if arguments[1] == "icon" {
            try SnapshotRenderer.renderIconSet(to: folder)
        } else {
            try SnapshotRenderer.renderScreens(to: folder)
        }
    } catch {
        print("Failed: \(error)")
        exit(1)
    }
}
