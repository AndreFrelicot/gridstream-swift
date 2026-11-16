//
//  VideoPlayerView.swift
//  gridstream-ipad
//

import AVFoundation
import SwiftUI

struct VideoPlayerView: UIViewRepresentable {
    let playerState: VideoPlayerState
    var framingMode: FramingMode = .fill
    var customScale: CGFloat = 1.0
    var customOffset: CGPoint = .zero

    func makeUIView(context: Context) -> PlayerSurfaceHostView {
        PlayerSurfaceHostView()
    }

    func updateUIView(_ host: PlayerSurfaceHostView, context: Context) {
        host.show(
            playerState.surface,
            framing: PlayerFraming(mode: framingMode, scale: customScale, offset: customOffset)
        )
    }

    static func dismantleUIView(_ host: PlayerSurfaceHostView, coordinator: ()) {
        host.releaseSurface()
    }
}

/// How a view frames the picture it shows.
struct PlayerFraming {
    var mode: FramingMode = .fill
    var scale: CGFloat = 1.0
    var offset: CGPoint = .zero
}

/// Where a `VideoPlayerView` shows its player's picture. The picture itself
/// is the player's `surface`, one view for the player's whole life: on a swap
/// between fullscreen and PiP, or between the grid and fullscreen, the views
/// pass it on instead of each attaching a layer of their own to the player.
/// A newly attached layer stays black until the player has drawn a frame into
/// it, which showed as black frames and a delay on every swap.
final class PlayerSurfaceHostView: UIView {
    private weak var surface: PlayerLayerView?
    private var framing = PlayerFraming()
    /// The picture was just taken over and has another view's size: the
    /// next layout sizes it at once, whatever animation runs.
    private var sizesSurfaceWithoutAnimation = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    /// Shows `newSurface`, framed as asked. The view takes the picture when
    /// it starts showing it, or when the picture is adrift. A picture that
    /// another view on screen took since stays there: this view is then
    /// leaving the screen, where a removal transition can still update it.
    func show(_ newSurface: PlayerLayerView, framing newFraming: PlayerFraming = PlayerFraming()) {
        framing = newFraming
        let previous = surface
        if previous !== newSurface {
            if let previous { stopShowing(previous) }
            surface = newSurface
            newSurface.hosts.add(self)
        }
        if newSurface.superview === self {
            newSurface.apply(framing)
        } else if previous !== newSurface || isAdrift(newSurface) {
            take(newSurface)
        }
    }

    /// Lets go of the picture when this view goes away. If it held the
    /// picture, a view on screen that still shows the player gets it back.
    func releaseSurface() {
        guard let surface else { return }
        self.surface = nil
        stopShowing(surface)
    }

    /// Moves the picture into this view, sized and framed for it.
    func take(_ surface: PlayerLayerView) {
        UIView.performWithoutAnimation {
            addSubview(surface)
            fitSurface()
        }
        sizesSurfaceWithoutAnimation = true
        surface.apply(framing)
    }

    /// SwiftUI takes a view off screen and puts it back as it was, without
    /// an update: leaving and entering the fullscreen mode faster than the
    /// transition does both. The picture follows the view that is on screen.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let surface else { return }
        if window == nil {
            guard surface.superview === self else { return }
            // Once UIKit is done moving this view.
            DispatchQueue.main.async { [weak surface] in
                surface?.returnToAHostOnScreen()
            }
        } else if surface.superview !== self, isAdrift(surface) {
            take(surface)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if sizesSurfaceWithoutAnimation {
            UIView.performWithoutAnimation { fitSurface() }
            sizesSurfaceWithoutAnimation = bounds.isEmpty
        } else {
            // Inside an animated size change the picture follows it.
            fitSurface()
        }
    }

    /// No view holds the picture, or the view that does is off screen and
    /// this one is not.
    private func isAdrift(_ surface: PlayerLayerView) -> Bool {
        surface.superview == nil || (surface.window == nil && window != nil)
    }

    private func stopShowing(_ surface: PlayerLayerView) {
        surface.hosts.remove(self)
        guard surface.superview === self else { return }
        surface.removeFromSuperview()
        surface.returnToAHostOnScreen()
    }

    /// Bounds and center, never the frame: a custom framing puts a transform
    /// on the picture, and a frame set under a transform is undefined.
    private func fitSurface() {
        guard let surface, surface.superview === self else { return }
        surface.bounds = CGRect(origin: .zero, size: bounds.size)
        surface.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

/// A player's picture: the view backed by its `AVPlayerLayer`. Owned by the
/// `VideoPlayerState`, shown inside a `PlayerSurfaceHostView`.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    /// The views showing this player. One of them holds the picture.
    let hosts = NSHashTable<PlayerSurfaceHostView>.weakObjects()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        clipsToBounds = true
    }

    /// Left off screen, the picture goes to a view on screen that shows the
    /// player.
    func returnToAHostOnScreen() {
        guard window == nil else { return }
        hosts.allObjects.first { $0.window != nil }?.take(self)
    }

    func apply(_ framing: PlayerFraming) {
        // Disable CALayer implicit animations for instant video gravity changes
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Set video gravity based on framing mode
        switch framing.mode {
        case .fill:
            playerLayer.videoGravity = .resizeAspectFill
            resetTransform()
        case .fit:
            playerLayer.videoGravity = .resizeAspect
            resetTransform()
        case .custom:
            // Custom mode uses resizeAspect as base, then applies transform
            playerLayer.videoGravity = .resizeAspect
            applyCustomTransform(scale: framing.scale, offset: framing.offset)
        }

        CATransaction.commit()
    }

    func applyCustomTransform(scale: CGFloat, offset: CGPoint) {
        // Create combined transform: scale first, then translate
        // Division by scale corrects for the scaled coordinate space
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: offset.x / scale, y: offset.y / scale)

        playerLayer.setAffineTransform(transform)
    }

    func resetTransform() {
        playerLayer.setAffineTransform(.identity)
    }
}

#Preview {
    VideoPlayerView(playerState: VideoPlayerState())
        .frame(width: 400, height: 300)
        .background(Color.black)
}

#Preview("Fill Mode") {
    VideoPlayerView(
        playerState: VideoPlayerState(),
        framingMode: .fill
    )
    .frame(width: 400, height: 300)
    .background(Color.black)
}

#Preview("Fit Mode") {
    VideoPlayerView(
        playerState: VideoPlayerState(),
        framingMode: .fit
    )
    .frame(width: 400, height: 300)
    .background(Color.black)
}

#Preview("Custom Mode") {
    VideoPlayerView(
        playerState: VideoPlayerState(),
        framingMode: .custom,
        customScale: 1.5,
        customOffset: CGPoint(x: 50, y: 30)
    )
    .frame(width: 400, height: 300)
    .background(Color.black)
}
