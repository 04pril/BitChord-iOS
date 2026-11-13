import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The pictures a widget draws, baked once per track (ports widget/MediaWidgetArt.kt).
///
/// A widget can't blur at run time: WidgetKit renders the view once into an archived snapshot, and
/// materials there don't sample what is under them. So, as on Android, the soft foot the transport
/// sits on and the 4×1's body are drawn here on the CPU, from the cover the app copied into the App
/// Group, and handed to the views as plain images.
struct WidgetArt {
    /// The cover, downscaled to what a widget can show.
    var cover: UIImage
    /// The cover blurred for the band at the foot of the 2×2 / 4×2 (masked in by the view so the
    /// blur ramps in over a region taller than the band, rather than starting at a hard edge).
    var softened: UIImage
    /// The cover blurred to colour and darkened: the 4×1's body.
    var body: UIImage
    /// Flat field behind the poster widgets, lifted into a band where white text stays readable.
    var background: UIColor
    /// Lighter tint of `background` for the decorative note.
    var note: UIColor
    /// The poster card's field: a darkened, broadly blurred Liquid Artwork colour wash.
    /// A dark, low-contrast field retains the cover’s warm/cool variation without neon saturation.
    var wash: UIImage

    /// Longest side kept. The widget archive holds these images for as long as it is on screen, and
    /// a medium widget is at most ~364 pt wide at 3×.
    static let maxPixels: CGFloat = 720

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Loads and bakes the art for a snapshot; nil without a saved cover (the view draws the
    /// placeholder gradient then).
    static func load(for snapshot: NowPlayingSnapshot?) -> WidgetArt? {
        guard let url = snapshot?.artworkFileURL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            return nil
        }
        return make(from: image)
    }

    static func make(from image: UIImage) -> WidgetArt? {
        guard let cover = downscaled(image), let input = CIImage(image: cover) else { return nil }
        let extent = input.extent
        // Radii relative to the picture, so a small cover and a large one blur alike.
        let side = max(extent.width, extent.height)
        guard let softened = blurred(input, radius: side * 0.035, darken: 0),
              let body = blurred(input, radius: side * 0.12, darken: 0.18) else { return nil }
        let poster = posterColors(from: cover)
        let wash = posterWash(input, cover: cover) ?? body
        return WidgetArt(cover: cover, softened: softened, body: body, background: poster.background, note: poster.note, wash: wash)
    }

    /// Liquid Artwork: a blurred sleeve stretched across the card, a second sleeve hue
    /// near the top, and a restrained dark foot behind the transport.
    private static func posterWash(_ input: CIImage, cover: UIImage) -> UIImage? {
        let side = max(input.extent.width, input.extent.height)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = input.clampedToExtent()
        blur.radius = Float(side * 0.115)
        guard var output = blur.outputImage?.cropped(to: input.extent) else { return nil }
        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.saturation = 1.6
        controls.brightness = 0
        controls.contrast = 1.0
        output = controls.outputImage?.cropped(to: input.extent) ?? output
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = output
        exposure.ev = -1.5
        output = exposure.outputImage?.cropped(to: input.extent) ?? output
        guard let cg = context.createCGImage(output, from: input.extent) else { return nil }
        let base = UIImage(cgImage: cg)
        let size = input.extent.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            base.draw(in: CGRect(origin: .zero, size: size))
            let accent = liquidAccent(from: cover)
            let colors = [accent.withAlphaComponent(0.7).cgColor, accent.withAlphaComponent(0).cgColor]
            if accent.cgColor.alpha > 0,
               let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                let center = CGPoint(x: size.width * 0.58, y: 0)
                renderer.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                    endCenter: center, endRadius: size.width * 0.82, options: .drawsBeforeStartLocation)
            }
            let shadow = [UIColor.black.withAlphaComponent(0.25).cgColor, UIColor.clear.cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shadow as CFArray, locations: [0, 1]) {
                let center = CGPoint(x: size.width * 0.54, y: size.height * 1.02)
                renderer.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                    endCenter: center, endRadius: size.width * 0.80, options: .drawsBeforeStartLocation)
            }
        }
    }

    /// A second sleeve hue supplies the soft upper light, instead of amplifying its most
    /// common colour into a flat saturated field. The tint is always read from this cover.
    private static func liquidAccent(from image: UIImage) -> UIColor {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let cg = image.cgImage, let ctx = CGContext(data: &bytes, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .clear }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let count = 24
        var weights = [CGFloat](repeating: 0, count: count)
        var hues = weights
        for index in stride(from: 0, to: bytes.count, by: 4) {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            UIColor(red: CGFloat(bytes[index]) / 255, green: CGFloat(bytes[index + 1]) / 255,
                    blue: CGFloat(bytes[index + 2]) / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            guard s > 0.35, b > 0.2 else { continue }
            let bin = min(Int(h * CGFloat(count)), count - 1)
            let weight = s * s * b
            weights[bin] += weight
            hues[bin] += h * weight
        }
        guard let dominant = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[dominant] > 0 else { return .clear }
        let secondary = weights.indices.filter {
            let distance = abs($0 - dominant)
            return min(distance, count - distance) > 2
        }.max(by: { weights[$0] < weights[$1] })
        guard let secondary, weights[secondary] > weights[dominant] * 0.06 else { return .clear }
        return UIColor(hue: hues[secondary] / weights[secondary], saturation: 0.48, brightness: 0.52, alpha: 1)
    }

    /// Used when a poster widget has no cover yet, or the cover has no colour of its own.
    static let posterFallbackBackground = UIColor(white: 0.45, alpha: 1)
    static let posterFallbackNote = UIColor(white: 0.82, alpha: 1)

    /// The poster field. White paper and flat grey are ignored, and the remaining hue with the most
    /// saturation wins — a navy surround behind a white sleeve stays navy, instead of averaging into
    /// grey the way a blur of the whole picture does. Brightness is then lifted into one mid band.
    static func posterColors(from image: UIImage) -> (background: UIColor, note: UIColor) {
        let side = 40
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let cg = image.cgImage,
              let context = CGContext(
                data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return (posterFallbackBackground, posterFallbackNote) }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        let binCount = 36
        var weight = [Double](repeating: 0, count: binCount)
        var satSum = [Double](repeating: 0, count: binCount)
        var hueSum = [Double](repeating: 0, count: binCount)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            UIColor(red: Double(bytes[index]) / 255, green: Double(bytes[index + 1]) / 255,
                    blue: Double(bytes[index + 2]) / 255, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            // Paper, highlights and flat grey carry no sleeve colour. Dark navy still does.
            guard saturation >= 0.12 else { continue }
            let bin = min(binCount - 1, Int(hue * CGFloat(binCount)))
            let sample = Double(saturation) * Double(saturation)
            weight[bin] += sample
            satSum[bin] += Double(saturation) * sample
            hueSum[bin] += Double(hue) * sample
        }
        guard let winner = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[winner] > 0.4 else {
            return (posterFallbackBackground, posterFallbackNote)
        }
        let hueOut = hueSum[winner] / weight[winner]
        let saturationIn = satSum[winner] / weight[winner]
        let saturationOut = saturationIn < 0.18 ? saturationIn : min(max(saturationIn * 1.15, 0.42), 0.68)
        let background = UIColor(hue: hueOut, saturation: saturationOut, brightness: 0.50, alpha: 1)
        let note = UIColor(hue: hueOut, saturation: min(saturationOut * 0.40, 0.28), brightness: 0.78, alpha: 1)
        return (background, note)
    }

    private static func downscaled(_ image: UIImage) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixels / max(size.width * image.scale, size.height * image.scale))
        let target = CGSize(width: (size.width * image.scale * scale).rounded(), height: (size.height * image.scale * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// A Gaussian blur that doesn't darken at the edges: the input is clamped to extent first, so
    /// the blur samples the border's own colour past the edge instead of transparent black
    /// (the "nothing to sample past the edge" problem MediaWidgetArt describes).
    private static func blurred(_ input: CIImage, radius: CGFloat, darken: CGFloat) -> UIImage? {
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = input.clampedToExtent()
        blur.radius = Float(radius)
        guard var output = blur.outputImage?.cropped(to: input.extent) else { return nil }
        if darken > 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = Float(-darken * 3)
            output = exposure.outputImage ?? output
        }
        guard let cg = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
