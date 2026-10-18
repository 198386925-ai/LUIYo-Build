import Foundation

/// Files kept in Application Support.
enum AppPaths {
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Leftover from the removed custom-background feature; cleared on launch.
    static var legacyBackgroundImage: URL {
        applicationSupport.appendingPathComponent("ThemeBackground.jpg")
    }
}
