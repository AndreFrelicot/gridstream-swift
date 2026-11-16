//
//  VideoErrorView.swift
//  gridstream-ipad
//

import AVFoundation
import SwiftUI

struct VideoErrorView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.yellow)

                VStack(spacing: 8) {
                    Text("Video Playback Error")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: onRetry) {
                    Label("Tap to Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .padding(24)
        }
    }

    private var errorMessage: String {
        let description = error.localizedDescription

        // Provide meaningful context for common AVPlayer errors
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return String(localized: "No internet connection. Check your network settings and try again.")
            case NSURLErrorTimedOut:
                return String(localized: "Connection timed out. The server may be unavailable.")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return String(localized: "Cannot reach the server. Make sure the server is running and accessible.")
            case NSURLErrorNetworkConnectionLost:
                return String(localized: "Network connection was lost during playback.")
            default:
                return String(localized: "Network error: \(description)")
            }
        }

        if nsError.domain == AVFoundationErrorDomain {
            switch nsError.code {
            case AVError.fileFormatNotRecognized.rawValue:
                return String(localized: "The video format is not supported.")
            case AVError.failedToParse.rawValue:
                return String(localized: "Unable to process the video file.")
            case AVError.contentIsNotAuthorized.rawValue:
                return String(localized: "You are not authorized to play this content.")
            case AVError.serverIncorrectlyConfigured.rawValue:
                return String(localized: "The streaming server is not configured correctly.")
            default:
                return String(localized: "Playback error: \(description)")
            }
        }

        return description
    }
}

#Preview("Network Error") {
    VideoErrorView(
        error: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        ),
        onRetry: {}
    )
    .frame(width: 400, height: 300)
}

#Preview("Server Error") {
    VideoErrorView(
        error: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [NSLocalizedDescriptionKey: "Could not connect to the server."]
        ),
        onRetry: {}
    )
    .frame(width: 400, height: 300)
}

#Preview("Format Error") {
    VideoErrorView(
        error: NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.fileFormatNotRecognized.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "The file format is not recognized."]
        ),
        onRetry: {}
    )
    .frame(width: 400, height: 300)
}

#Preview("Generic Error") {
    VideoErrorView(
        error: NSError(
            domain: "TestDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "An unexpected error occurred while loading the video."]
        ),
        onRetry: {}
    )
    .frame(width: 400, height: 300)
}
