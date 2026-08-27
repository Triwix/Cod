import SwiftUI

/// A circular zoomed view of the image around `point`, with crosshairs — the
/// thing that makes pixel-exact edges possible under a fingertip.
struct MagnifierLoupe: View {
    let image: UIImage
    let geometry: SelectionGeometry
    /// Point of interest, in view coordinates.
    let point: CGPoint

    var diameter: CGFloat = 112
    var zoom: CGFloat = 2.75

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .frame(
                    width: geometry.displayRect.width * zoom,
                    height: geometry.displayRect.height * zoom
                )
                .offset(x: imageOffset.x, y: imageOffset.y)

            crosshair
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
        .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 4).blur(radius: 2))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .allowsHitTesting(false)
    }

    /// Places the point of interest dead centre in the loupe.
    private var imageOffset: CGPoint {
        let local = CGPoint(
            x: point.x - geometry.displayRect.minX,
            y: point.y - geometry.displayRect.minY
        )
        return CGPoint(
            x: diameter / 2 - local.x * zoom,
            y: diameter / 2 - local.y * zoom
        )
    }

    private var crosshair: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.85))
                .frame(width: diameter, height: 1)
            Rectangle()
                .fill(.white.opacity(0.85))
                .frame(width: 1, height: diameter)
            Rectangle()
                .strokeBorder(.yellow, lineWidth: 1)
                .frame(width: zoom, height: zoom)
        }
        .frame(width: diameter, height: diameter)
        .blendMode(.difference)
    }
}
