//
//  CloudSharingSheet.swift
//  Sonidea
//
//  UIViewControllerRepresentable wrapper for UICloudSharingController
//  so it can be presented as a SwiftUI sheet.
//

import SwiftUI
import CloudKit

/// Wraps UICloudSharingController for presentation in SwiftUI
struct CloudSharingSheet: UIViewControllerRepresentable {
    let controller: UICloudSharingController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
