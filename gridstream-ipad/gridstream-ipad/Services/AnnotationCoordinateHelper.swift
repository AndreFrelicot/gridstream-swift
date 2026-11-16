import CoreGraphics
import Foundation

struct AnnotationCoordinateHelper {
    /// Convert a view point to normalized 0-1 video coordinates
    static func normalize(point: CGPoint, videoRect: CGRect) -> CGPoint {
        guard videoRect.width > 0, videoRect.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - videoRect.origin.x) / videoRect.width,
            y: (point.y - videoRect.origin.y) / videoRect.height
        )
    }

    /// Convert normalized coordinates back to view coordinates for rendering
    static func denormalize(point: CGPoint, videoRect: CGRect) -> CGPoint {
        CGPoint(
            x: videoRect.origin.x + point.x * videoRect.width,
            y: videoRect.origin.y + point.y * videoRect.height
        )
    }

    /// Snap time to nearest frame boundary
    static func snapToFrame(time: Double, frameRate: Double) -> Double {
        guard frameRate > 0 else { return time }
        let frameNumber = round(time * frameRate)
        return frameNumber / frameRate
    }

    /// Compute the video rect within the view for the current framing mode
    static func computeVideoRect(videoSize: CGSize, viewSize: CGSize, framingMode: FramingMode) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }

        let videoAspect = videoSize.width / videoSize.height
        let viewAspect = viewSize.width / viewSize.height

        switch framingMode {
        case .fit, .custom:
            // Video fits entirely within view (letterboxed/pillarboxed).
            // A custom framing zooms and pans from there: the player draws
            // it with the same gravity, the caller applies the zoom and pan.
            if videoAspect > viewAspect {
                // Video is wider — fit to width, letterbox top/bottom
                let height = viewSize.width / videoAspect
                let y = (viewSize.height - height) / 2
                return CGRect(x: 0, y: y, width: viewSize.width, height: height)
            } else {
                // Video is taller — fit to height, pillarbox left/right
                let width = viewSize.height * videoAspect
                let x = (viewSize.width - width) / 2
                return CGRect(x: x, y: 0, width: width, height: viewSize.height)
            }
        case .fill:
            // Video fills the view (may be cropped)
            if videoAspect > viewAspect {
                // Video is wider — fill height, crop sides
                let width = viewSize.height * videoAspect
                let x = (viewSize.width - width) / 2
                return CGRect(x: x, y: 0, width: width, height: viewSize.height)
            } else {
                // Video is taller — fill width, crop top/bottom
                let height = viewSize.width / videoAspect
                let y = (viewSize.height - height) / 2
                return CGRect(x: 0, y: y, width: viewSize.width, height: height)
            }
        }
    }
}
