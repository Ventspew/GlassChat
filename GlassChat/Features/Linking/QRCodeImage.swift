import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCodeImage {
    @MainActor
    static func make(from string: String, dimension: CGFloat = 240) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

struct QRCodeView: View {
    let code: String
    var size: CGFloat = 240

    var body: some View {
        Group {
            if let image = QRCodeImage.make(from: code, dimension: size) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .accessibilityLabel("WhatsApp pairing QR code")
            } else {
                ContentUnavailableView("QR unavailable", systemImage: "qrcode")
                    .frame(width: size, height: size)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
