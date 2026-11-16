//
//  PiPDismissGestureView.swift
//  gridstream-ipad
//
//  2-finger diagonal swipe gesture for dismissing/restoring PiP tiles.
//  Uses UIPanGestureRecognizer since SwiftUI's DragGesture doesn't support multi-finger detection.
//
//  The gesture recognizer is installed on the UIKit window so that the gesture view itself
//  doesn't block single-tap gestures on underlying SwiftUI layers (e.g. controls show/hide).
//

import SwiftUI

// MARK: - DiagonalCorner

enum DiagonalCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

// MARK: - PiPDismissGestureView

struct PiPDismissGestureView: UIViewRepresentable {
    let onGestureChanged: (CGPoint, CGPoint, CGSize) -> Void  // (translation, velocity, viewSize)
    let onGestureEnded: (CGPoint, CGPoint, CGSize) -> Void    // (translation, velocity, viewSize)

    func makeUIView(context: Context) -> GestureInstallView {
        let view = GestureInstallView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: GestureInstallView, context: Context) {
        context.coordinator.onGestureChanged = onGestureChanged
        context.coordinator.onGestureEnded = onGestureEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onGestureChanged: onGestureChanged, onGestureEnded: onGestureEnded)
    }

    // MARK: - Pass-Through UIView

    /// UIView that installs the 2-finger pan gesture on the window rather than on itself,
    /// so it never blocks single-touch gestures on underlying SwiftUI layers.
    class GestureInstallView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                coordinator?.installOnWindow(window)
            } else {
                coordinator?.removeFromWindow()
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var onGestureChanged: (CGPoint, CGPoint, CGSize) -> Void
        var onGestureEnded: (CGPoint, CGPoint, CGSize) -> Void

        /// Whether the gesture has been validated as diagonal
        private var isDiagonalValidated = false
        /// Whether the gesture was rejected (not diagonal)
        private var isRejected = false
        /// Minimum movement before validating direction
        private let validationThreshold: CGFloat = 10

        // Only touched on the main actor, and in deinit once nothing else holds the object.
        nonisolated(unsafe) private var panGesture: UIPanGestureRecognizer?

        init(onGestureChanged: @escaping (CGPoint, CGPoint, CGSize) -> Void,
             onGestureEnded: @escaping (CGPoint, CGPoint, CGSize) -> Void) {
            self.onGestureChanged = onGestureChanged
            self.onGestureEnded = onGestureEnded
        }

        deinit {
            // The window does not retain the recognizer's target, so it must go
            // now, not on a later main-actor turn. UIKit objects are released on
            // the main thread; anywhere else the recognizer is left in place.
            guard let pan = panGesture, Thread.isMainThread else { return }
            MainActor.assumeIsolated {
                pan.view?.removeGestureRecognizer(pan)
            }
        }

        func installOnWindow(_ window: UIWindow) {
            // Avoid double-install
            guard panGesture == nil else { return }

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            window.addGestureRecognizer(pan)
            panGesture = pan
        }

        func removeFromWindow() {
            if let pan = panGesture {
                pan.view?.removeGestureRecognizer(pan)
                panGesture = nil
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            let viewSize = view.bounds.size

            switch recognizer.state {
            case .began:
                isDiagonalValidated = false
                isRejected = false

            case .changed:
                if isRejected { return }

                if !isDiagonalValidated {
                    let distance = sqrt(translation.x * translation.x + translation.y * translation.y)
                    guard distance >= validationThreshold else { return }

                    // Check diagonal angle: must be between 20° and 70° from horizontal
                    let absX = abs(translation.x)
                    let absY = abs(translation.y)
                    guard absX > 0.001 else {
                        isRejected = true
                        return
                    }
                    let angle = atan2(absY, absX) * 180 / .pi
                    if angle < 20 || angle > 70 {
                        isRejected = true
                        return
                    }
                    isDiagonalValidated = true
                }

                let translationPoint = CGPoint(x: translation.x, y: translation.y)
                let velocityPoint = CGPoint(x: velocity.x, y: velocity.y)
                onGestureChanged(translationPoint, velocityPoint, viewSize)

            case .ended, .cancelled:
                if isRejected || !isDiagonalValidated {
                    isDiagonalValidated = false
                    isRejected = false
                    return
                }

                let translationPoint = CGPoint(x: translation.x, y: translation.y)
                let velocityPoint = CGPoint(x: velocity.x, y: velocity.y)
                onGestureEnded(translationPoint, velocityPoint, viewSize)

                isDiagonalValidated = false
                isRejected = false

            default:
                break
            }
        }
    }
}
