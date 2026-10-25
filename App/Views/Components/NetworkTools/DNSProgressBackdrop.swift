import SwiftUI

struct DNSProgressBackdrop: View, Animatable {
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let track = DNSProgressFlow.track(in: size)
                let outline = Path(track)
                context.clip(to: outline)
                context.fill(outline, with: .color(Color(red: 0.025, green: 0.055, blue: 0.10)))

                // A quiet grid gives the moving energy a stable frame of reference.
                var grid = Path()
                for x in stride(from: track.minX, through: track.maxX, by: 24) {
                    grid.move(to: CGPoint(x: x, y: track.minY))
                    grid.addLine(to: CGPoint(x: x, y: track.maxY))
                }
                for y in stride(from: track.minY, through: track.maxY, by: 12) {
                    grid.move(to: CGPoint(x: track.minX, y: y))
                    grid.addLine(to: CGPoint(x: track.maxX, y: y))
                }
                context.stroke(grid, with: .color(.cyan.opacity(0.055)), lineWidth: 0.5)

                let filled = CGRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height)
                var fillContext = context
                fillContext.clip(to: Path(filled))
                // A continuous color field spans the entire fill; no tiled strips or resetting scan lines.
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let stops = (0...32).map { index -> Gradient.Stop in
                    let position = Double(index) / 32
                    let color = DNSProgressFlow.components(position: position, time: time)
                    return .init(
                        color: Color(.sRGBLinear, red: color.red, green: color.green, blue: color.blue, opacity: 0.86),
                        location: position
                    )
                }
                fillContext.fill(Path(filled), with: .linearGradient(
                    Gradient(stops: stops),
                    startPoint: CGPoint(x: track.minX, y: track.midY),
                    endPoint: CGPoint(x: filled.maxX, y: track.midY)
                ))

                // Bloom extends around the true frontier without adding horizontal border lines.
                if progress > 0 {
                    let beam = CGRect(x: filled.maxX - 0.75, y: track.minY, width: 1.5, height: track.height)
                    for (radius, opacity) in [(10.0, 0.55), (3.0, 0.8)] {
                        var glow = context
                        glow.addFilter(.blur(radius: radius))
                        glow.drawLayer { layer in
                            layer.fill(Path(beam), with: .color(.cyan.opacity(opacity)))
                        }
                    }
                    context.fill(Path(beam), with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .cyan.opacity(0.4), location: 0),
                            .init(color: .cyan, location: 0.25),
                            .init(color: .white.opacity(0.95), location: 0.5),
                            .init(color: .cyan, location: 0.75),
                            .init(color: .cyan.opacity(0.4), location: 1)
                        ]),
                        startPoint: CGPoint(x: filled.maxX, y: track.minY),
                        endPoint: CGPoint(x: filled.maxX, y: track.maxY)
                    ))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum DNSProgressFlow {
    static func track(in size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size)
    }

    static func chromaticPhase(position: Double, time: TimeInterval) -> Double {
        // A wavelength wider than the fill avoids a narrow traveling band.
        0.5 + 0.5 * cos(2 * .pi * (position * 0.35 - time))
    }

    static func components(position: Double, time: TimeInterval) -> (red: Double, green: Double, blue: Double) {
        let phase = chromaticPhase(position: position, time: time)
        let red = 0.01 + 0.018 * phase
        let blue = 0.55 + 0.4 * phase
        // Keep linear-sRGB luminance constant: animate chroma, not a scanning brightness peak.
        let green = (0.24 - 0.2126 * red - 0.0722 * blue) / 0.7152
        return (red, green, blue)
    }
}
