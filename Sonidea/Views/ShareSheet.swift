//
//  ShareSheet.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes

        // iPad safety: configure popover source so UIActivityViewController
        // doesn't crash if presented outside SwiftUI's .sheet() context
        if let popover = controller.popoverPresentationController {
            popover.permittedArrowDirections = []
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        if let popover = uiViewController.popoverPresentationController,
           popover.sourceView == nil {
            popover.sourceView = uiViewController.view
            popover.sourceRect = CGRect(
                x: uiViewController.view.bounds.midX,
                y: uiViewController.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
    }
}
