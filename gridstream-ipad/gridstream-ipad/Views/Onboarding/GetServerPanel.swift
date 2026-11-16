//
//  GetServerPanel.swift
//  gridstream-ipad
//
//  Where to get GridStream Server for Mac: the link, a way to send it to
//  the Mac (AirDrop, Messages, Mail), a copy button and a QR code.
//

import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct GetServerPanel: View {
    var url: URL = DemoController.serverDownloadURL

    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                Text(url.host().map { $0 + url.path() } ?? url.absoluteString)
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)

                Text("Free, for macOS 15.6 or later. Open it on your Mac, choose the folders that hold your videos, and it serves them to this iPad.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    ShareLink(item: url, subject: Text("GridStream Server for Mac"), message: Text("Download GridStream Server for Mac")) {
                        Label("Send to my Mac", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    Button {
                        UIPasteboard.general.url = url
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }

            if let qrCode = Self.qrCode(for: url) {
                Image(uiImage: qrCode)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 132, height: 132)
                    .padding(10)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("QR code of the download link")
            }
        }
    }

    private static func qrCode(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage,
              let cgImage = CIContext().createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
