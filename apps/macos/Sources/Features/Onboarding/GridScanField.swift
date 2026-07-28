import SwiftUI

struct GridScanField: View {
    @State private var animationStartedAt = Date()
    @State private var pointerFrom = CGPoint(x: 0.5, y: 0.5)
    @State private var pointerTo = CGPoint(x: 0.5, y: 0.5)
    @State private var pointerMotionStartedAt = Date()
    @State private var pointerMotionDuration: TimeInterval = 0.18

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let time = CGFloat(timeline.date.timeIntervalSince(animationStartedAt))
                    let pointer = pointerPosition(at: timeline.date)
                    let background = Path(CGRect(origin: .zero, size: size))
                    context.fill(
                        background,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(red: 0.025, green: 0.025, blue: 0.035),
                                Color(red: 0.050, green: 0.050, blue: 0.065),
                                Color(red: 0.020, green: 0.020, blue: 0.028)
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: size.height)
                        )
                    )

                    let vanishingPoint = CGPoint(
                        x: size.width * (0.5 + (pointer.x - 0.5) * 0.13),
                        y: size.height * (0.46 + (pointer.y - 0.5) * 0.09)
                    )
                    let outer = [
                        CGPoint(x: -size.width * 0.20, y: -size.height * 0.18),
                        CGPoint(x: size.width * 1.20, y: -size.height * 0.18),
                        CGPoint(x: size.width * 1.20, y: size.height * 1.18),
                        CGPoint(x: -size.width * 0.20, y: size.height * 1.18)
                    ]

                    drawRays(
                        context: &context,
                        size: size,
                        vanishingPoint: vanishingPoint,
                        outer: outer,
                        time: time
                    )

                    for index in 1...22 {
                        let normalized = CGFloat(index) / 22
                        let depth = pow(normalized, 1.72)
                        let jitter = sin(time * 1.65 + CGFloat(index) * 2.31) * 0.0018
                        let ring = ringPath(
                            vanishingPoint: vanishingPoint,
                            outer: outer,
                            amount: min(1, max(0, depth + jitter))
                        )
                        drawGridStroke(
                            context: &context,
                            path: ring,
                            size: size,
                            lineWidth: 1,
                            baseOpacity: 0.42
                        )
                    }

                    drawScan(
                        context: &context,
                        size: size,
                        vanishingPoint: vanishingPoint,
                        outer: outer,
                        time: time
                    )

                    for index in 0..<120 {
                        let seed = CGFloat(index)
                        let noiseFrame = floor(time * 18)
                        let x = fractional(sin(seed * 12.9898 + noiseFrame * 0.031) * 43_758.5453) * size.width
                        let y = fractional(sin((seed + 19) * 78.233 + noiseFrame * 0.047) * 12_345.678) * size.height
                        let radius = 0.28 + CGFloat(index % 3) * 0.22
                        let grain = Path(
                            ellipseIn: CGRect(
                                x: x - radius,
                                y: y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                        )
                        context.fill(
                            grain,
                            with: .color(Color.white.opacity(0.012 + Double(index % 4) * 0.008))
                        )
                    }
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    movePointer(
                        to: CGPoint(
                            x: min(1, max(0, location.x / max(1, proxy.size.width))),
                            y: min(1, max(0, location.y / max(1, proxy.size.height)))
                        ),
                        duration: 0.16
                    )
                case .ended:
                    movePointer(
                        to: CGPoint(x: 0.5, y: 0.5),
                        duration: 0.75
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    private func movePointer(to target: CGPoint, duration: TimeInterval) {
        let now = Date()
        let current = pointerPosition(at: now)
        pointerFrom = current
        pointerTo = target
        pointerMotionStartedAt = now
        pointerMotionDuration = duration
    }

    private func pointerPosition(at date: Date) -> CGPoint {
        let elapsed = date.timeIntervalSince(pointerMotionStartedAt)
        let progress = min(1, max(0, elapsed / max(0.001, pointerMotionDuration)))
        let eased = 1 - pow(1 - progress, 3)
        return CGPoint(
            x: pointerFrom.x + (pointerTo.x - pointerFrom.x) * eased,
            y: pointerFrom.y + (pointerTo.y - pointerFrom.y) * eased
        )
    }

    private func drawRays(
        context: inout GraphicsContext,
        size: CGSize,
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        time: CGFloat
    ) {
        let segments = 9
        for edge in 0..<4 {
            let start = outer[edge]
            let end = outer[(edge + 1) % 4]
            for index in 0...segments {
                let amount = CGFloat(index) / CGFloat(segments)
                var endpoint = CGPoint(
                    x: start.x + (end.x - start.x) * amount,
                    y: start.y + (end.y - start.y) * amount
                )
                let jitter = sin(time * 1.8 + CGFloat(edge * 13 + index) * 1.41) * 1.1
                if edge % 2 == 0 {
                    endpoint.x += jitter
                } else {
                    endpoint.y += jitter
                }
                var ray = Path()
                ray.move(to: vanishingPoint)
                ray.addLine(to: endpoint)
                drawGridStroke(
                    context: &context,
                    path: ray,
                    size: size,
                    lineWidth: 1,
                    baseOpacity: 0.38
                )
            }
        }
    }

    private func drawScan(
        context: inout GraphicsContext,
        size: CGSize,
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        time: CGFloat
    ) {
        let duration: CGFloat = 2.0
        let delay: CGFloat = 2.0
        guard time >= delay else { return }
        let pingPongTime = (time - delay).truncatingRemainder(dividingBy: duration * 2)
        let phase = pingPongTime < duration
            ? pingPongTime / duration
            : 1 - (pingPongTime - duration) / duration
        let taper: CGFloat = 0.49
        let phaseWindow = smoother01(0, taper, phase)
            * (1 - smoother01(1 - taper, 1, phase))
        let eased = phase * phase * (3 - 2 * phase)
        let depth = 0.07 + eased * 0.91
        let scan = ringPath(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: depth
        )

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            layer.stroke(
                scan,
                with: .color(Color.white.opacity(0.24 * Double(phaseWindow))),
                lineWidth: 28
            )
        }
        context.stroke(
            chromaticPath(scan, size: size, delta: -0.005),
            with: .color(Color(red: 1.0, green: 0.18, blue: 0.22).opacity(0.26 * Double(phaseWindow))),
            lineWidth: 1.2
        )
        context.stroke(
            chromaticPath(scan, size: size, delta: 0.005),
            with: .color(Color(red: 0.12, green: 0.62, blue: 1.0).opacity(0.28 * Double(phaseWindow))),
            lineWidth: 1.2
        )
        context.stroke(
            scan,
            with: .color(Color.white.opacity(0.40 * Double(phaseWindow))),
            lineWidth: 1.5
        )

        let inner = ringPoints(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: max(0.02, depth - 0.040)
        )
        let outside = ringPoints(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: min(1, depth + 0.040)
        )
        var band = Path()
        band.move(to: inner[0])
        inner.dropFirst().forEach { band.addLine(to: $0) }
        outside.reversed().forEach { band.addLine(to: $0) }
        band.closeSubpath()
        context.fill(
            band,
            with: .color(Color.white.opacity(0.10 * Double(phaseWindow)))
        )
    }

    private func drawGridStroke(
        context: inout GraphicsContext,
        path: Path,
        size: CGSize,
        lineWidth: CGFloat,
        baseOpacity: Double
    ) {
        context.stroke(
            chromaticPath(path, size: size, delta: -0.005),
            with: .color(Color(red: 1.0, green: 0.16, blue: 0.20).opacity(0.14)),
            lineWidth: lineWidth
        )
        context.stroke(
            chromaticPath(path, size: size, delta: 0.005),
            with: .color(Color(red: 0.10, green: 0.58, blue: 1.0).opacity(0.16)),
            lineWidth: lineWidth
        )
        context.stroke(
            path,
            with: .color(Color(red: 0.518, green: 0.518, blue: 0.518).opacity(baseOpacity)),
            lineWidth: lineWidth
        )
    }

    private func chromaticPath(_ path: Path, size: CGSize, delta: CGFloat) -> Path {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: 1 + delta, y: 1 + delta)
            .translatedBy(x: -center.x, y: -center.y)
        return path.applying(transform)
    }

    private func smoother01(_ start: CGFloat, _ end: CGFloat, _ value: CGFloat) -> CGFloat {
        let progress = min(1, max(0, (value - start) / max(0.00001, end - start)))
        return progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }

    private func ringPath(
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        amount: CGFloat
    ) -> Path {
        let points = ringPoints(
            vanishingPoint: vanishingPoint,
            outer: outer,
            amount: amount
        )
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func ringPoints(
        vanishingPoint: CGPoint,
        outer: [CGPoint],
        amount: CGFloat
    ) -> [CGPoint] {
        outer.map { point in
            CGPoint(
                x: vanishingPoint.x + (point.x - vanishingPoint.x) * amount,
                y: vanishingPoint.y + (point.y - vanishingPoint.y) * amount
            )
        }
    }

    private func fractional(_ value: CGFloat) -> CGFloat {
        value - floor(value)
    }
}
