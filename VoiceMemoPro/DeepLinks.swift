//
//  DeepLinks.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

// MARK: - URL Scheme Setup Instructions
//
// To enable the custom URL scheme (voicememopro://record), you need to add
// URL Types to your Xcode project:
//
// 1. Select your project in the Project Navigator
// 2. Select your app target
// 3. Go to the "Info" tab
// 4. Expand "URL Types"
// 5. Click "+" to add a new URL Type
// 6. Set:
//    - Identifier: $(PRODUCT_BUNDLE_IDENTIFIER)
//    - URL Schemes: voicememopro
//    - Role: Editor
//
// Alternatively, this is configured in Info.plist via CFBundleURLTypes.
//
// Once configured, the app will respond to:
//   - voicememopro://record  → Opens app and starts recording
//

import UIKit

/// Deep link helpers for opening system screens and external apps
enum DeepLinks {

    /// The custom URL scheme for this app
    static let appScheme = "voicememopro"

    /// URL to trigger recording via deep link
    static var recordURL: URL? {
        URL(string: "\(appScheme)://record")
    }

    // MARK: - System Deep Links

    /// Opens the app's Settings page in the iOS Settings app
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    /// Opens the Shortcuts app
    /// Note: This opens the Shortcuts app but cannot navigate to a specific screen
    static func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - URL Parsing

    /// Checks if a URL is a "record" deep link
    static func isRecordURL(_ url: URL) -> Bool {
        // Handle voicememopro://record
        if url.scheme == appScheme {
            return url.host == "record" || url.path == "/record"
        }
        return false
    }
}
