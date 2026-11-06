import AppKit
import SwiftUI

/// The app icon, drawn in code so the Dock icon and the one inside the app can't drift apart.
enum AppIcon {
    private static let brand = NSColor(hex: 0x5EDBC0)
    private static let ink = NSColor(hex: 0x0B1512)

    /// `margin` leaves the padding macOS expects around icons. Inside the app the tile fills its frame.
    static func png(pixels: Int, margin: Bool) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let s = CGFloat(pixels) / (margin ? 1 : 0.8)
        if !margin {
            let transform = NSAffineTransform()
            transform.translateX(by: -s * 0.1, yBy: -s * 0.1)
            transform.concat()
        }

        brand.setFill()
        NSBezierPath(roundedRect: CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8), xRadius: s * 0.18, yRadius: s * 0.18).fill()

        ink.setFill()
        let bubble = NSBezierPath(roundedRect: CGRect(x: s * 0.24, y: s * 0.36, width: s * 0.52, height: s * 0.38), xRadius: s * 0.09, yRadius: s * 0.09)
        bubble.move(to: CGPoint(x: s * 0.34, y: s * 0.38))
        bubble.line(to: CGPoint(x: s * 0.30, y: s * 0.25))
        bubble.line(to: CGPoint(x: s * 0.47, y: s * 0.38))
        bubble.close()
        bubble.fill()

        brand.setFill()
        for (y, width) in [(CGFloat(0.59), CGFloat(0.34)), (0.49, 0.22)] {
            NSBezierPath(roundedRect: CGRect(x: s * 0.33, y: s * y, width: s * width, height: s * 0.05), xRadius: s * 0.025, yRadius: s * 0.025).fill()
        }
        return rep.representation(using: .png, properties: [:])
    }

    static let image: NSImage = png(pixels: 256, margin: false).flatMap(NSImage.init(data:)) ?? NSImage()
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: AppIcon.image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("Tact")
    }
}

/// The icon and name together, for the top of a window.
struct BrandMark: View {
    var iconSize: CGFloat = 30

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    var body: some View {
        HStack(spacing: 9) {
            AppIconView(size: iconSize)
            VStack(alignment: .leading, spacing: 0) {
                Text("Tact").font(.system(size: 14, weight: .semibold))
                Text("Version \(version)").font(.system(size: 11)).foregroundStyle(Color.textSecondary)
            }
        }
    }
}
