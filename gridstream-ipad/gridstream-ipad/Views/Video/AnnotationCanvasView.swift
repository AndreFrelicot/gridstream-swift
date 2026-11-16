import PencilKit
import SwiftUI

private class NoMenuCanvasView: PKCanvasView {
    /// Called after layout so the representable can load strokes once the view
    /// finally has a non-zero size (the first updateUIView often runs before).
    var onLayout: (() -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct AnnotationCanvasView: UIViewRepresentable {
    var videoSize: CGSize
    var framingMode: FramingMode
    var customScale: CGFloat
    var customOffset: CGPoint
    var frameTime: Double
    var existingStrokes: [StrokeData]
    /// The video the shown frame belongs to. Remembered with the loaded frame
    /// so strokes are saved to it even after the tile has switched videos.
    var target: AnnotationManager.Target?
    /// Reports the extracted strokes together with the frame time and video
    /// they belong to. The debounced save can fire after the user has moved to
    /// another frame or video, so the caller must not persist against the
    /// player's live time or the manager's current video.
    var onStrokesChanged: (([StrokeData], Double, AnnotationManager.Target?) -> Void)?
    var onFingerTap: (() -> Void)?
    var onFingerDoubleTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = NoMenuCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.overrideUserInterfaceStyle = .dark
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas

        // Load strokes once the canvas actually has a size. The first
        // updateUIView can run with zero bounds (skipped), and no further
        // updateUIView arrives until some input changes — which is why the
        // drawing only appeared after toggling the resize/framing button.
        canvas.onLayout = { [weak coordinator = context.coordinator, weak canvas] in
            guard let coordinator, let canvas else { return }
            coordinator.loadIfBoundsReady(canvas: canvas)
        }

        // Set up tool picker so the user can change pen, color, width, eraser, etc.
        let toolPicker = Self.makeToolPicker()
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.toolPicker = toolPicker

        // becomeFirstResponder must be deferred — the view isn't in a window yet
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }

        // Add finger tap gesture recognizers so taps pass through to show/hide controls
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFingerDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        canvas.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFingerTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        singleTap.require(toFail: doubleTap)
        canvas.addGestureRecognizer(singleTap)

        return canvas
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        // Flush any pending debounced save before teardown. Otherwise a drawing
        // made within ~1s of toggling pencil mode off is lost: the Coordinator is
        // deallocated before the debounce fires, so onStrokesChanged never runs,
        // the annotation is never persisted, and re-opening pencil mode has
        // nothing to reload.
        coordinator.flushPendingSave(from: uiView)
        coordinator.toolPicker?.setVisible(false, forFirstResponder: uiView)
        coordinator.toolPicker?.removeObserver(uiView)
        coordinator.toolPicker = nil
        uiView.resignFirstResponder()
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self

        // Check if transform changed even while drawing, so we can defer the reload
        let scaleChanged = abs(customScale - context.coordinator.lastCustomScale) > 0.001
        let offsetChanged = abs(customOffset.x - context.coordinator.lastCustomOffset.x) > 0.1
            || abs(customOffset.y - context.coordinator.lastCustomOffset.y) > 0.1
        let framingModeChanged = framingMode != context.coordinator.lastFramingMode
        let transformChanged = scaleChanged || offsetChanged || framingModeChanged

        // Don't reload strokes while the user is actively drawing — except when
        // the frame itself changed. Waiting out the debounce there would leave
        // the previous frame's drawing painted over the new frame, so persist
        // what was drawn (against the frame it belongs to) and reload now.
        if context.coordinator.isDrawing {
            let frameChanged = (context.coordinator.lastLoadedFrameTime
                .map { abs(frameTime - $0) >= 0.001 } ?? true)
                || !(target?.isSameVideo(as: context.coordinator.lastLoadedTarget) ?? true)
            guard frameChanged else {
                if transformChanged {
                    context.coordinator.needsDeferredReload = true
                }
                return
            }
            context.coordinator.flushPendingSave(from: uiView)
            context.coordinator.isDrawing = false
        }

        let viewSize = uiView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        // Only reload when the frame time actually changes (different frame),
        // strokes count has changed, or the zoom/pan transform has changed
        if let lastTime = context.coordinator.lastLoadedFrameTime,
           abs(frameTime - lastTime) < 0.001,
           target?.isSameVideo(as: context.coordinator.lastLoadedTarget) ?? true,
           context.coordinator.lastLoadedStrokesCount == existingStrokes.count,
           !transformChanged {
            return
        }

        context.coordinator.lastCustomScale = customScale
        context.coordinator.lastCustomOffset = customOffset
        context.coordinator.lastFramingMode = framingMode

        let videoRect = AnnotationCoordinateHelper.computeVideoRect(
            videoSize: videoSize, viewSize: viewSize, framingMode: framingMode
        )
        let transformedRect = applyTransform(to: videoRect, viewSize: viewSize)
        context.coordinator.loadStrokes(existingStrokes, frameTime: frameTime, videoRect: transformedRect, into: uiView)
    }

    /// Builds the tool picker without the lasso tool. Selecting strokes offers
    /// cut / copy / duplicate / insert-space, which makes no sense for a frame
    /// annotation — those actions move or remove strokes that are meant to stay
    /// pinned to what they point at in the video, and the drawing is persisted
    /// on a debounce, so an accidental selection edit is saved as-is.
    /// Custom item lists need iOS 18; older systems keep the stock picker.
    private static func makeToolPicker() -> PKToolPicker {
        if #available(iOS 26.0, *) {
            let items = PKToolPicker.defaultToolItems.filter { !($0 is PKToolPickerLassoItem) }
            return PKToolPicker(toolItems: items)
        }
        if #available(iOS 18.0, *) {
            return PKToolPicker(toolItems: [
                PKToolPickerInkingItem(type: .pen),
                PKToolPickerInkingItem(type: .pencil),
                PKToolPickerInkingItem(type: .marker),
                PKToolPickerInkingItem(type: .monoline),
                PKToolPickerInkingItem(type: .fountainPen),
                PKToolPickerInkingItem(type: .watercolor),
                PKToolPickerInkingItem(type: .crayon),
                PKToolPickerEraserItem(type: .bitmap),
                PKToolPickerRulerItem()
            ])
        }
        return PKToolPicker()
    }

    private func applyTransform(to rect: CGRect, viewSize: CGSize) -> CGRect {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        let scaledWidth = rect.width * customScale
        let scaledHeight = rect.height * customScale
        let scaledX = centerX + (rect.midX - centerX) * customScale + customOffset.x - scaledWidth / 2
        let scaledY = centerY + (rect.midY - centerY) * customScale + customOffset.y - scaledHeight / 2

        return CGRect(x: scaledX, y: scaledY, width: scaledWidth, height: scaledHeight)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: AnnotationCanvasView
        weak var canvas: PKCanvasView?
        var toolPicker: PKToolPicker?
        var isDrawing = false
        var lastLoadedFrameTime: Double?
        var lastLoadedTarget: AnnotationManager.Target?
        var lastLoadedStrokesCount: Int = -1
        var lastCustomScale: CGFloat = 1.0
        var lastCustomOffset: CGPoint = .zero
        var lastFramingMode: FramingMode = .fill
        /// Set when a transform or frame change arrives while isDrawing is true.
        /// Cleared after a deferred reload when isDrawing turns false.
        var needsDeferredReload = false
        private var saveWorkItem: DispatchWorkItem?
        private var isLoadingExternalStrokes = false

        init(parent: AnnotationCanvasView) {
            self.parent = parent
        }

        @objc func handleFingerTap() {
            parent.onFingerTap?()
        }

        @objc func handleFingerDoubleTap() {
            parent.onFingerDoubleTap?()
        }

        func loadStrokes(_ strokes: [StrokeData], frameTime: Double, videoRect: CGRect, into canvas: PKCanvasView) {
            lastLoadedFrameTime = frameTime
            lastLoadedTarget = parent.target ?? lastLoadedTarget
            lastLoadedStrokesCount = strokes.count
            isLoadingExternalStrokes = true
            defer { isLoadingExternalStrokes = false }

            guard !strokes.isEmpty else {
                if !canvas.drawing.strokes.isEmpty {
                    canvas.drawing = PKDrawing()
                }
                return
            }

            var pkStrokes: [PKStroke] = []

            for strokeData in strokes {
                let color = UIColor(hex: strokeData.color) ?? .red
                let ink = PKInk(.pen, color: color.withAlphaComponent(CGFloat(strokeData.opacity)))

                var points: [PKStrokePoint] = []
                for pt in strokeData.points {
                    let viewPoint = AnnotationCoordinateHelper.denormalize(
                        point: CGPoint(x: pt.x, y: pt.y),
                        videoRect: videoRect
                    )
                    let strokePoint = PKStrokePoint(
                        location: viewPoint,
                        timeOffset: 0,
                        size: CGSize(width: CGFloat(strokeData.width), height: CGFloat(strokeData.width)),
                        opacity: CGFloat(strokeData.opacity),
                        force: CGFloat(pt.pressure),
                        azimuth: 0,
                        altitude: .pi / 2
                    )
                    points.append(strokePoint)
                }

                guard points.count >= 2 else { continue }

                let path = PKStrokePath(controlPoints: points, creationDate: Date())
                let pkStroke = PKStroke(ink: ink, path: path)
                pkStrokes.append(pkStroke)
            }

            var drawing = PKDrawing()
            drawing.strokes = pkStrokes
            canvas.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Ignore changes triggered by loading external strokes
            guard !isLoadingExternalStrokes else { return }

            isDrawing = true

            // Cancel any pending debounced save
            saveWorkItem?.cancel()

            // Debounce: only save after user stops drawing for 1 second
            let workItem = DispatchWorkItem { [weak self] in
                self?.extractAndSave(from: canvasView)
            }
            saveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }

        /// Runs any pending debounced save immediately (e.g. when the canvas is
        /// torn down right after drawing) so the strokes are not lost.
        func flushPendingSave(from canvas: PKCanvasView) {
            guard saveWorkItem != nil else { return }
            saveWorkItem?.cancel()
            saveWorkItem = nil
            extractAndSave(from: canvas)
        }

        private func extractAndSave(from canvasView: PKCanvasView) {
            let viewSize = canvasView.bounds.size
            guard viewSize.width > 0, viewSize.height > 0 else {
                isDrawing = false
                return
            }

            let videoRect = AnnotationCoordinateHelper.computeVideoRect(
                videoSize: parent.videoSize,
                viewSize: viewSize,
                framingMode: parent.framingMode
            )
            let transformedRect = parent.applyTransform(to: videoRect, viewSize: viewSize)

            var strokeDataArray: [StrokeData] = []

            for stroke in canvasView.drawing.strokes {
                let color = stroke.ink.color.hexString
                let opacity = Double(stroke.ink.color.cgColor.alpha)

                var points: [StrokePoint] = []
                let path = stroke.path
                for i in stride(from: path.startIndex, to: path.endIndex, by: 1) {
                    let pt = path[i]
                    let normalized = AnnotationCoordinateHelper.normalize(
                        point: pt.location,
                        videoRect: transformedRect
                    )
                    points.append(StrokePoint(
                        x: normalized.x,
                        y: normalized.y,
                        pressure: Double(pt.force)
                    ))
                }

                // Downsample points to reduce payload size
                let sampled = Self.downsample(points, maxPoints: 100)

                let width = Double(stroke.path.first.map { $0.size.width } ?? 5)
                strokeDataArray.append(StrokeData(
                    color: color,
                    width: width,
                    opacity: opacity,
                    points: sampled
                ))
            }

            // The canvas holds the strokes of the frame it was last loaded for.
            // Reporting the player's live time instead would move the drawing
            // onto whatever frame the user navigated to during the debounce.
            parent.onStrokesChanged?(strokeDataArray, lastLoadedFrameTime ?? parent.frameTime, lastLoadedTarget ?? parent.target)

            // Keep isDrawing true briefly after save callback to prevent immediate reload
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.isDrawing = false

                // If a transform or frame change arrived while we were drawing,
                // reload now so the canvas shows the current frame's strokes
                if self.needsDeferredReload {
                    self.needsDeferredReload = false
                    self.reloadStrokesWithCurrentTransform()
                }
            }
        }

        /// Loads strokes once the canvas has a valid size, if the current frame's
        /// strokes have not been loaded yet. Driven by layoutSubviews so the
        /// drawing paints as soon as the view is sized, without needing an
        /// external update (e.g. toggling the resize/framing button).
        func loadIfBoundsReady(canvas: PKCanvasView) {
            guard !isDrawing else { return }
            let size = canvas.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            // Already loaded this frame's strokes at this count? Nothing to do.
            if let lastTime = lastLoadedFrameTime,
               abs(parent.frameTime - lastTime) < 0.001,
               parent.target?.isSameVideo(as: lastLoadedTarget) ?? true,
               lastLoadedStrokesCount == parent.existingStrokes.count {
                return
            }
            let videoRect = AnnotationCoordinateHelper.computeVideoRect(
                videoSize: parent.videoSize, viewSize: size, framingMode: parent.framingMode
            )
            let transformedRect = parent.applyTransform(to: videoRect, viewSize: size)
            lastCustomScale = parent.customScale
            lastCustomOffset = parent.customOffset
            lastFramingMode = parent.framingMode
            loadStrokes(parent.existingStrokes, frameTime: parent.frameTime, videoRect: transformedRect, into: canvas)
        }

        /// Reloads strokes using the current parent transform values.
        /// Called when a transform change was deferred because the user was drawing.
        private func reloadStrokesWithCurrentTransform() {
            guard let canvas = canvas else { return }
            let viewSize = canvas.bounds.size
            guard viewSize.width > 0, viewSize.height > 0 else { return }

            let videoRect = AnnotationCoordinateHelper.computeVideoRect(
                videoSize: parent.videoSize, viewSize: viewSize, framingMode: parent.framingMode
            )
            let transformedRect = parent.applyTransform(to: videoRect, viewSize: viewSize)
            lastCustomScale = parent.customScale
            lastCustomOffset = parent.customOffset
            lastFramingMode = parent.framingMode
            loadStrokes(parent.existingStrokes, frameTime: parent.frameTime, videoRect: transformedRect, into: canvas)
        }

        /// Reduces the number of points in a stroke while preserving shape
        static func downsample(_ points: [StrokePoint], maxPoints: Int) -> [StrokePoint] {
            guard points.count > maxPoints else { return points }
            var result: [StrokePoint] = [points[0]]
            let step = Double(points.count - 1) / Double(maxPoints - 1)
            for i in 1..<(maxPoints - 1) {
                let index = Int(Double(i) * step)
                result.append(points[min(index, points.count - 1)])
            }
            result.append(points[points.count - 1])
            return result
        }
    }
}

// MARK: - UIColor Hex Helpers

private extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        switch hexSanitized.count {
        case 6:
            self.init(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        case 8:
            self.init(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
