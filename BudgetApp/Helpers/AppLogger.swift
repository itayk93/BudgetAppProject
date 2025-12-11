import Foundation

/// Lightweight, centralized logging helper used across the app.
enum AppLogger {
    static func log(_ message: String, force: Bool = false) {
        #if DEBUG
        print(message)
        #else
        if force {
            print(message)
        }
        #endif
    }
}
