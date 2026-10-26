import SwiftUI
import AppKit

/// The transfer progress strip: a station wagon drives along the bottom of the window to the
/// lodge while the files copy and verify. The trail behind it is blue while copying and turns
/// green once everything is verified, and the lodge lights up when the wagon arrives.
///
/// Only Maddy's dark version is approved, so the strip is dark in both appearances. With
/// Reduce Motion it is a still scene at the current progress (no scrolling or particles). It
/// stops redrawing while the window is hidden. The maths lives in `WagonScene`.
struct WagonStrip: View {
    /// The offload's real progress (0…1); the wagon eases towards it.
    let progress: Double
    /// Everything copied and verified: the wagon parks and the lodge lights up.
    let arrived: Bool
    /// Cancelled or failed: the wagon stops where it is.
    let stopped: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driver: WagonDriver
    @State private var windowVisible = true

    init(progress: Double, arrived: Bool, stopped: Bool) {
        self.progress = progress
        self.arrived = arrived
        self.stopped = stopped
        // A strip that appears mid-offload starts where the offload is (no drive from 0 %).
        _driver = State(initialValue: WagonDriver(progress: arrived ? 1 : progress))
    }

    static let height = WagonScene.height

    var body: some View {
        TimelineView(.animation(minimumInterval: minimumInterval, paused: paused)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let frame = advance(to: time)
            WagonCanvas(frame: frame)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous))
        .background(WindowVisibilityReader(isVisible: $windowVisible))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    /// Nothing moves once the lodge is lit except the fireflies and the smoke, so 30 fps is plenty.
    private var minimumInterval: Double? {
        driver.arrival >= 1 || stopped ? 1.0 / 30 : nil
    }

    private var paused: Bool {
        reduceMotion || !windowVisible || Self.demoStillTime != nil
    }

    private func advance(to time: Double) -> WagonFrame {
        if let still = Self.demoStillTime {
            driver.still(progress: progress, time: still, arrived: arrived)
            return WagonFrame(driver: driver, time: still, animated: true)
        }
        if reduceMotion {
            driver.settle(progress: progress, arrived: arrived)
            return WagonFrame(driver: driver, time: 0, animated: false)
        }
        driver.advance(to: time, target: progress, arrived: arrived, stopped: stopped)
        return WagonFrame(driver: driver, time: time, animated: true)
    }

    /// Screenshots: `-LodgeDemoWagonTime 2` freezes the strip the way the motion study's
    /// still mode draws it, `t` seconds into a drive (Debug builds only).
    static var demoStillTime: Double? {
        #if DEBUG
        guard DemoData.launchState != nil,
              let value = UserDefaults.standard.string(forKey: "LodgeDemoWagonTime") else { return nil }
        return Double(value)
        #else
        return nil
        #endif
    }
}

/// One frame of the strip, in design units.
struct WagonFrame {
    var progress: Double
    var distance: Double
    var speed: Double
    /// The eased arrival (0 → 1).
    var arrival: Double
    var time: Double
    /// False with Reduce Motion: no smoke, fireflies, dust or bounce.
    var animated: Bool

    init(driver: WagonDriver, time: Double, animated: Bool) {
        progress = driver.progress
        distance = driver.distance
        speed = animated ? driver.speed : 0
        arrival = WagonScene.arrivalEase(driver.arrival)
        self.time = time
        self.animated = animated
    }
}

// MARK: - Drawing

private struct WagonCanvas: View {
    let frame: WagonFrame

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            WagonPainter(frame: frame, width: size.width).paint(&context)
        }
    }
}

/// Draws the scene back to front, following the motion study's layer order.
private struct WagonPainter {
    let frame: WagonFrame
    let width: Double

    private typealias Scene = WagonScene
    private var designWidth: Double { Scene.designWidth }
    /// Things placed on the right of the 1060-wide design stay anchored to the right edge.
    private var rightShift: Double { width - designWidth }
    private var wagonX: Double { Scene.wagonX(progress: frame.progress, width: width) }
    private var lodgeOffset: Double { Scene.lodgeOffset(progress: frame.progress) }

    func paint(_ context: inout GraphicsContext) {
        sky(&context)
        tiles(&context, "WagonMountainsFar", speed: Scene.Layer.farMountains, period: designWidth, size: CGSize(width: 1060, height: 112))
        haze(&context)
        tiles(&context, "WagonHills", speed: Scene.Layer.hills, period: designWidth, size: CGSize(width: 1060, height: 112))
        tiles(&context, "WagonPines", speed: Scene.Layer.pines, period: designWidth, size: CGSize(width: 1067, height: 112))
        lodge(&context)
        road(&context)
        trail(&context)
        effects(&context)
        wagon(&context)
        foreground(&context)
        // The hairline along the top edge.
        context.fill(Path(CGRect(x: 0, y: 0, width: width, height: 0.5)), with: .color(.white.opacity(0.08)))
    }

    // MARK: Sky

    private func sky(_ context: inout GraphicsContext) {
        let stops: [Gradient.Stop] = [
            .init(color: Color(hex: 0x1D1E22), location: 0), .init(color: Color(hex: 0x232A35), location: 0.45),
            .init(color: Color(hex: 0x3A3A47), location: 0.75), .init(color: Color(hex: 0x5A4A4E), location: 1),
        ]
        context.fill(Path(CGRect(x: 0, y: 0, width: width, height: Scene.height)),
                     with: .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: 0, y: Scene.height)))

        let stars = context.resolve(Image("WagonStars"))
        var x = 0.0
        while x < width {
            context.draw(stars, in: CGRect(x: x, y: 0, width: 1060.43, height: 40))
            x += designWidth
        }
        if frame.arrival > 0 {
            var extra = context
            extra.opacity = frame.arrival
            extra.draw(context.resolve(Image("WagonStarsExtra")), in: CGRect(x: width - 520, y: 0, width: 520, height: 40))
        }

        // The sun sinks behind the ridge as the wagon arrives.
        let centre = CGPoint(x: width - 155, y: 60 + 30 * frame.arrival)
        let sunColor = Color(hex: 0xF1B985)
        var glow = context
        glow.opacity = 1 - 0.75 * frame.arrival
        glow.fill(Path(ellipseIn: CGRect(x: centre.x - 60, y: centre.y - 60, width: 120, height: 120)),
                  with: .radialGradient(Gradient(stops: [
                      .init(color: sunColor.opacity(0.55), location: 0), .init(color: sunColor.opacity(0.18), location: 0.35),
                      .init(color: sunColor.opacity(0), location: 1),
                  ]), center: centre, startRadius: 0, endRadius: 60))
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 9.5, y: centre.y - 9.5, width: 19, height: 19)),
                     with: .color(sunColor.opacity(0.9)))
    }

    private func haze(_ context: inout GraphicsContext) {
        let haze = Color(hex: 0x5A4A4E)
        context.fill(Path(CGRect(x: 0, y: 40, width: width, height: 50)),
                     with: .linearGradient(Gradient(colors: [haze.opacity(0), haze.opacity(0.55)]),
                                           startPoint: CGPoint(x: 0, y: 40), endPoint: CGPoint(x: 0, y: 90)))
    }

    /// A scrolling layer: its tile repeated across the strip.
    private func tiles(_ context: inout GraphicsContext, _ name: String, speed: Double, period: Double, size: CGSize, x shift: Double = 0) {
        let image = context.resolve(Image(name))
        var x = Scene.layerOffset(distance: frame.distance, speed: speed, period: period) + shift
        while x < width {
            context.draw(image, in: CGRect(x: x, y: 0, width: size.width, height: size.height))
            x += period
        }
    }

    // MARK: Lodge

    private func lodge(_ context: inout GraphicsContext) {
        let offset = lodgeOffset
        guard Scene.isLodgeVisible(offset: offset) else { return }
        var lodge = context
        lodge.translateBy(x: rightShift + offset, y: 0)
        let rect = CGRect(x: 931, y: 31.5, width: 130, height: 66.9)
        let ease = frame.arrival
        if ease < 1 {
            lodge.draw(lodge.resolve(Image("WagonLodgeUnlit")), in: rect)
        }
        if ease > 0 {
            var lit = lodge
            lit.opacity = ease
            lit.draw(lodge.resolve(Image("WagonLodgeLit")), in: rect)
        }
        guard frame.animated else { return }

        // Chimney smoke, a little stronger once someone's home.
        lodge.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.3))
            for puff in Scene.smoke(arrival: ease, time: frame.time) where puff.opacity > 0 {
                layer.fill(circle(puff), with: .color(Color(hex: 0xCFCBC6).opacity(puff.opacity)))
            }
        }
        if ease > 0 {
            let firefly = lodge.resolve(Image("WagonFirefly"))
            for index in Scene.fireflies.indices {
                let fly = Scene.firefly(index, time: frame.time)
                var dot = lodge
                dot.opacity = ease * fly.opacity
                dot.draw(firefly, in: CGRect(x: fly.x - 3, y: fly.y - 3, width: 6, height: 6))
            }
        }
    }

    // MARK: Road

    private func road(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 89.5, width: width, height: 16)), with: .color(Color(hex: 0x202022)))
        context.fill(Path(CGRect(x: 0, y: 89.5, width: width, height: 1)), with: .color(Color(hex: 0x38383B)))
        // The dashes repeat every 28 pt, so scrolling by `distance mod 28` never shows a seam.
        let dashes = context.resolve(Image("WagonRoadDashes"))
        var x = Scene.layerOffset(distance: frame.distance, speed: Scene.Layer.road, period: 28)
        while x < width {
            context.draw(dashes, in: CGRect(x: x, y: 97, width: 2120, height: 2))
            x += 2100
        }
        context.fill(Path(CGRect(x: 0, y: 105.5, width: width, height: 6.5)), with: .color(Color(hex: 0x141A18)))
    }

    /// The progress line on the road behind the wagon: blue while copying, green once verified.
    private func trail(_ context: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: 96.8, width: Scene.trailWidth(progress: frame.progress, width: width), height: 2.2)
        let path = Path(roundedRect: rect, cornerRadius: 1.1)
        let ends = (CGPoint(x: rect.minX, y: 0), CGPoint(x: rect.maxX, y: 0))
        let ease = frame.arrival
        if ease < 1 {
            let blue = Color(hex: 0x0A84FF)
            var copying = context
            copying.opacity = 1 - ease
            copying.fill(path, with: .linearGradient(Gradient(colors: [blue.opacity(0.25), blue.opacity(0.9)]),
                                                     startPoint: ends.0, endPoint: ends.1))
        }
        if ease > 0 {
            let green = Color(hex: 0x30D158)
            var verified = context
            verified.opacity = ease
            verified.fill(path, with: .linearGradient(Gradient(colors: [green.opacity(0.2), green.opacity(0.85)]),
                                                      startPoint: ends.0, endPoint: ends.1))
        }
    }

    // MARK: Wagon

    private func effects(_ context: inout GraphicsContext) {
        guard frame.speed > 0.01 else { return }
        var lines = context
        lines.opacity = frame.speed
        lines.draw(context.resolve(Image("WagonSpeedLines")), in: CGRect(x: wagonX - 70, y: 64, width: 65, height: 17))
        guard frame.animated else { return }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.2))
            for puff in Scene.dust(wagonX: wagonX, speed: frame.speed, time: frame.time) {
                layer.fill(circle(puff), with: .color(Color(hex: 0xCDBBA0).opacity(puff.opacity)))
            }
        }
    }

    private func wagon(_ context: inout GraphicsContext) {
        var car = context
        car.translateBy(x: wagonX, y: 0)
        let ease = frame.arrival

        car.drawLayer { shadow in
            shadow.addFilter(.blur(radius: 1.6))
            shadow.fill(Path(ellipseIn: CGRect(x: 2, y: 94.2, width: 92, height: 4.8)), with: .color(.black.opacity(0.45)))
        }
        var beam = car
        beam.opacity = 1 - 0.85 * ease
        beam.draw(car.resolve(Image("WagonHeadlightBeam")), in: CGRect(x: 93, y: 78, width: 57, height: 16))

        var body = car
        if frame.animated {
            body.translateBy(x: 0, y: Scene.bob(speed: frame.speed, time: frame.time))
        }
        body.draw(car.resolve(Image("WagonRoofCargo")), in: CGRect(x: 13, y: 43, width: 78, height: 20))
        body.draw(car.resolve(Image("WagonBody")), in: CGRect(x: 2, y: 58, width: 97, height: 28))
        body.drawLayer { glow in
            glow.addFilter(.blur(radius: 2.2))
            glow.fill(Path(ellipseIn: CGRect(x: 90.2, y: 69.7, width: 10, height: 10)),
                      with: .color(Color(hex: 0xFFE9B8).opacity(0.18 * (1 - 0.7 * ease))))
        }

        let well = car.resolve(Image("WagonWheelWell"))
        let wheel = car.resolve(Image("WagonWheel"))
        let angle = Angle(degrees: Scene.wheelAngle(distance: frame.distance))
        for (wellX, centre) in [(12.0, CGPoint(x: 21, y: 85)), (69.0, CGPoint(x: 78, y: 85))] {
            car.draw(well, in: CGRect(x: wellX, y: 76, width: 18, height: 9))
            var tyre = car
            tyre.translateBy(x: centre.x, y: centre.y)
            tyre.rotate(by: angle)
            tyre.draw(wheel, in: CGRect(x: -7, y: -7, width: 14, height: 14))
        }
    }

    // MARK: Foreground

    /// The foreground grass, pines and shrubs, scrolling at twice the road's speed with a real
    /// horizontal-only motion blur: the layer is drawn once per sample of a 1-D Gaussian
    /// (offset along x, weighted) and the samples are added together.
    private func foreground(_ context: inout GraphicsContext) {
        let kernel = Scene.horizontalBlurKernel(sigma: Scene.foregroundBlur(speed: frame.speed),
                                                taps: frame.speed > 0.35 ? 9 : 5)
        let grass = context.resolve(Image("WagonForegroundGrass"))
        let pines = context.resolve(Image("WagonForegroundPines"))
        let shrubs = context.resolve(Image("WagonForegroundShrubs"))
        let grassX = Scene.layerOffset(distance: frame.distance, speed: Scene.Layer.foreground, period: 2120)
        let tileX = Scene.layerOffset(distance: frame.distance, speed: Scene.Layer.foreground, period: designWidth)

        blurred(&context, kernel: kernel) { layer in
            var x = grassX
            while x < width {
                layer.draw(grass, in: CGRect(x: x - 2.97, y: 0, width: 2122.9, height: 112))
                x += 2120
            }
            x = tileX
            while x < width {
                layer.draw(shrubs, in: CGRect(x: x, y: 0, width: 1060, height: 122))
                x += designWidth
            }
        }

        context.drawLayer { pinesLayer in
            blurred(&pinesLayer, kernel: kernel) { layer in
                var x = tileX
                while x < width {
                    layer.draw(pines, in: CGRect(x: x, y: 0, width: 1060, height: 120))
                    x += designWidth
                }
            }
            clearPines(&pinesLayer)
        }
    }

    /// Keeps the lodge in view: no foreground pine stands in front of it once it is close.
    private func clearPines(_ context: inout GraphicsContext) {
        let strength = Scene.smooth(0.93, 1, frame.progress)
        guard strength > 0, Scene.isLodgeVisible(offset: lodgeOffset) else { return }
        let feather = 20.0
        let left = rightShift + lodgeOffset + 931 - feather
        let span = 130 + 2 * feather
        let edge = feather / span
        context.blendMode = .destinationOut
        context.opacity = strength
        context.fill(Path(CGRect(x: left, y: 0, width: span, height: Scene.height)),
                     with: .linearGradient(Gradient(stops: [
                         .init(color: .black.opacity(0), location: 0), .init(color: .black, location: edge),
                         .init(color: .black, location: 1 - edge), .init(color: .black.opacity(0), location: 1),
                     ]), startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + span, y: 0)))
    }

    private func blurred(_ context: inout GraphicsContext, kernel: [(offset: Double, weight: Double)],
                         draw: (inout GraphicsContext) -> Void) {
        if kernel.count == 1 {
            draw(&context)
            return
        }
        context.drawLayer { sum in
            sum.blendMode = .plusLighter
            for sample in kernel {
                sum.opacity = sample.weight
                sum.drawLayer { tap in
                    tap.translateBy(x: sample.offset, y: 0)
                    draw(&tap)
                }
            }
        }
    }

    private func circle(_ puff: WagonScene.Puff) -> Path {
        Path(ellipseIn: CGRect(x: puff.x - puff.radius, y: puff.y - puff.radius,
                               width: puff.radius * 2, height: puff.radius * 2))
    }
}

// MARK: - Window visibility

/// Reports whether the window is on screen (not minimised, hidden or fully covered), so the
/// strip can stop animating when nobody can see it.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = { [binding = $isVisible] visible in
            if binding.wrappedValue != visible { binding.wrappedValue = visible }
        }
        return view
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {}

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            report()
        }

        private func report() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }
    }
}
