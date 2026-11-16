import SwiftUI

struct CaptureFrameButton: View {
    let isCapturing: Bool
    let showSuccess: Bool
    let showError: Bool
    let action: () -> Void
    var isCompact: Bool = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    var body: some View {
        Button(action: action) {
            Group {
                if isCapturing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(isCompact ? 0.5 : 0.7)
                } else if showSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.white)
                } else if showError {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .background(
                Circle()
                    .fill(showSuccess ? Color.green : showError ? Color.red : Color.black.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .accessibilityLabel(
            isCapturing ? "Capturing frame" :
            showSuccess ? "Frame captured" :
            showError ? "Capture failed" :
            "Capture frame"
        )
    }
}
