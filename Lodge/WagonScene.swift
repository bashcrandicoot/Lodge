import Foundation

/// The maths behind the station-wagon progress strip (see `WagonStrip`): where the wagon is,
/// how fast the scenery scrolls, when the lodge comes into view and how the arrival plays out.
/// Everything here is plain numbers so it can be unit-tested; the drawing lives in
/// `WagonStripView.swift`.
///
/// The numbers come from Maddy's motion study (`wagon-progress.html`) and the Figma file
/// ("Lodge Wagon"). The strip was designed 1060 × 112 pt; things on the right (the sun, the
/// lodge, the spot where the wagon parks) stay anchored to the right edge when the window is
/// wider or narrower.
enum WagonScene {
    // MARK: Constants (design units: points in a 1060 × 112 strip)

    static let designWidth = 1060.0
    static let height = 112.0
    /// Road points per second at full speed.
    static let baseSpeed = 330.0
    /// Seconds for the lodge to light up once the wagon has parked.
    static let arrivalDuration = 1.4
    /// The wagon's left edge at 0 %.
    static let startX = 18.0
    /// The wagon's left edge at 100 % is this far from the right edge (842 in a 1060 strip).
    static let parkInsetFromRight = 218.0
    /// The scenery starts slowing down here…
    static let slowdownStart = 0.85
    /// …and the lodge is somewhere down the road (off screen) from here on.
    static let lodgeApproachStart = 0.72
    /// The lodge isn't drawn while it is further than this past its parking spot.
    static let lodgeDrawDistance = 200.0
    /// The foreground's horizontal motion blur (σ, in points) at full speed.
    static let foregroundBlurAtFullSpeed = 2.4

    /// How fast each layer scrolls compared with the road.
    enum Layer {
        static let farMountains = 0.036
        static let hills = 0.08
        static let pines = 0.2
        static let road = 1.0
        static let foreground = 2.0
    }

    // MARK: Helpers

    static func clamp(_ x: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
        min(high, max(low, x))
    }

    static func mix(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

    /// Smoothstep: 0 below `edge0`, 1 above `edge1`, an S-curve in between.
    static func smooth(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let k = clamp((x - edge0) / (edge1 - edge0))
        return k * k * (3 - 2 * k)
    }

    // MARK: Progress → scene

    /// How fast the scenery moves (1 = full speed): full speed until 85 %, easing to a stop at 100 %.
    static func speed(progress p: Double) -> Double {
        p >= 1 ? 0 : 1 - smooth(slowdownStart, 1, p)
    }

    /// Where the wagon parks (its left edge) in a strip `width` points wide.
    static func parkX(width: Double) -> Double { width - parkInsetFromRight }

    /// The wagon's left edge: it drives from the left edge (0 %) to its parking spot (100 %).
    static func wagonX(progress p: Double, width: Double = designWidth) -> Double {
        startX + clamp(p) * (parkX(width: width) - startX)
    }

    /// The width of the road's progress line (it ends just under the wagon).
    static func trailWidth(progress p: Double, width: Double = designWidth) -> Double {
        wagonX(progress: p, width: width) + 10
    }

    /// How far down the road the lodge still is (0 = in place, at 100 %); `.infinity` before
    /// the last stretch. The lodge rides on the road, so this is the road distance the wagon
    /// still has to cover on the motion study's slow-down curve.
    static func lodgeOffset(progress p: Double) -> Double {
        if p >= 1 { return 0 }
        if p <= lodgeApproachStart { return .infinity }
        return max(0, SlowdownCurve.shared.finalDistance - SlowdownCurve.shared.distance(atProgress: p))
    }

    /// The lodge is only drawn when it is close enough to be (nearly) on screen.
    static func isLodgeVisible(offset: Double) -> Bool { offset <= lodgeDrawDistance }

    /// A scrolling layer's x position (≤ 0) for its tiles, each `period` points wide.
    static func layerOffset(distance: Double, speed: Double, period: Double = designWidth) -> Double {
        let travelled = (distance * speed).truncatingRemainder(dividingBy: period)
        let wrapped = travelled < 0 ? travelled + period : travelled
        return wrapped == 0 ? 0 : -wrapped
    }

    /// Wheel spoke rotation in degrees (the tyre has a 6.6 pt radius, so it rolls with the road).
    static func wheelAngle(distance: Double) -> Double {
        let degrees = (distance / 6.6 * 57.3).truncatingRemainder(dividingBy: 360)
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// The body's bounce on the road (points, ≤ 0), only while moving.
    static func bob(speed v: Double, time t: Double) -> Double {
        -0.7 * v * (0.5 + 0.5 * sin(t * 15))
    }

    /// The foreground's horizontal-only blur (σ, in points).
    static func foregroundBlur(speed v: Double) -> Double { foregroundBlurAtFullSpeed * clamp(v) }

    /// The arrival curve: 0 → 1 over `arrivalDuration` seconds once parked, smoothed.
    static func arrivalEase(_ arrival: Double) -> Double { smooth(0, 1, arrival) }

    /// Samples of a horizontal Gaussian (offset in points, weight) that sum to 1. The
    /// foreground is drawn once per sample and added together: a real 1-D blur along x only.
    static func horizontalBlurKernel(sigma: Double, taps: Int = 11) -> [(offset: Double, weight: Double)] {
        guard sigma > 0.05, taps > 1 else { return [(0, 1)] }
        let half = Double(taps - 1) / 2
        let spacing = 2.5 * sigma / half          // covers ±2.5σ
        var samples: [(offset: Double, weight: Double)] = []
        for index in 0..<taps {
            let x = (Double(index) - half) * spacing
            samples.append((x, exp(-(x * x) / (2 * sigma * sigma))))
        }
        let total = samples.reduce(0) { $0 + $1.weight }
        return samples.map { ($0.offset, $0.weight / total) }
    }

    /// Moves the shown progress towards the real progress without jumping (time constant `tau`).
    /// It never goes backwards and snaps once it is close.
    static func easedProgress(current: Double, target: Double, dt: Double, tau: Double = 0.45) -> Double {
        let target = clamp(target)
        guard target > current else { return current }
        let next = current + (target - current) * (1 - exp(-max(0, dt) / tau))
        return target - next < 0.0005 ? target : next
    }

    // MARK: Particles (positions in design units, relative to the wagon or the lodge)

    struct Puff: Equatable {
        var x: Double
        var y: Double
        var radius: Double
        var opacity: Double
    }

    /// Five dust puffs kicked up behind the rear wheel.
    static func dust(wagonX wx: Double, speed v: Double, time t: Double) -> [Puff] {
        (0..<5).map { index in
            let phase = (t * 0.9 + Double(index) / 5).truncatingRemainder(dividingBy: 1)
            return Puff(x: wx + 12 - phase * 30, y: 95 - phase * 5, radius: 2.5 + phase * 6,
                        opacity: (1 - phase) * 0.26 * v)
        }
    }

    /// Six smoke puffs rising from the chimney (x relative to the lodge's design position).
    static func smoke(arrival ease: Double, time t: Double) -> [Puff] {
        let strength = mix(0.18, 1, ease)
        return (0..<6).map { index in
            let phase = (t * 0.28 + Double(index) / 6).truncatingRemainder(dividingBy: 1)
            return Puff(x: lodgeCentreX + 20.7 - phase * 9 + sin(phase * 6 + Double(index)) * 1.6,
                        y: lodgeGround - 53 - phase * 30,
                        radius: 1.6 + phase * 5.5,
                        opacity: strength * 0.42 * sin(.pi * min(1, phase * 1.15)))
        }
    }

    /// The lodge's centre and ground line in the 1060-wide design.
    static let lodgeCentreX = 992.0
    static let lodgeGround = 90.0

    /// Fireflies around the lodge: (x, y, phase).
    static let fireflies: [(x: Double, y: Double, phase: Double)] = [
        (lodgeCentreX - 48, lodgeGround - 12, 0), (lodgeCentreX - 36, lodgeGround - 30, 1.7),
        (lodgeCentreX + 46, lodgeGround - 22, 0.9), (lodgeCentreX + 38, lodgeGround - 6, 2.6),
        (lodgeCentreX - 62, lodgeGround - 4, 3.3), (lodgeCentreX + 56, lodgeGround - 38, 4.1),
    ]

    static func firefly(_ index: Int, time t: Double) -> Puff {
        let fly = fireflies[index]
        let tt = t + fly.phase
        return Puff(x: fly.x + sin(tt * 0.9) * 5, y: fly.y + cos(tt * 1.3) * 3, radius: 3,
                    opacity: 0.25 + 0.75 * pow(0.5 + 0.5 * sin(tt * 2.6), 2))
    }
}

/// The motion study's slow-down: progress eases from 72 % to 100 % over 5.5 s while the scenery
/// slows. The road distance covered along it tells us how far away the lodge is at a given
/// progress, so it lands exactly where the wagon parks.
struct SlowdownCurve {
    static let shared = SlowdownCurve()

    static let duration = 5.5
    private static let step = 1.0 / 240

    /// Road distance (points) covered by each step, summed: `cumulative[i]` is the distance at `i × step`.
    private let cumulative: [Double]
    let finalDistance: Double

    init() {
        let count = Int(((Self.duration + 0.1) / Self.step).rounded(.up)) + 2
        var sums = [0.0]
        sums.reserveCapacity(count + 1)
        for index in 0..<count {
            let p = Self.progress(atTime: Double(index) * Self.step)
            sums.append(sums[index] + WagonScene.speed(progress: p) * Self.step * WagonScene.baseSpeed)
        }
        cumulative = sums
        finalDistance = sums[sums.count - 1]
    }

    /// Progress along the study's curve `t` seconds into the final stretch.
    static func progress(atTime t: Double) -> Double {
        if t >= duration { return 1 }
        let start = WagonScene.lodgeApproachStart
        return start + (1 - start) * (1 - pow(1 - max(0, t) / duration, 2.2))
    }

    /// The inverse of `progress(atTime:)`.
    static func time(atProgress p: Double) -> Double {
        let start = WagonScene.lodgeApproachStart
        if p <= start { return 0 }
        if p >= 1 { return duration }
        return duration * (1 - pow(1 - (p - start) / (1 - start), 1 / 2.2))
    }

    /// Road distance covered on the curve by the time it reaches progress `p`.
    func distance(atProgress p: Double) -> Double {
        let position = Self.time(atProgress: p) / Self.step
        let index = min(cumulative.count - 2, max(0, Int(position.rounded(.down))))
        let fraction = position - Double(index)
        return cumulative[index] + (cumulative[index + 1] - cumulative[index]) * fraction
    }
}

/// Drives the strip from the offload's real progress, frame by frame: eases the shown progress
/// towards the real one, scrolls the road, and plays the arrival once everything is verified.
/// A plain class (not observed): the strip's `TimelineView` asks it for a new frame each tick.
final class WagonDriver {
    /// The shown progress (eased towards the real progress).
    private(set) var progress: Double
    /// Road distance travelled so far (points).
    private(set) var distance: Double = 0
    /// 0 → 1 over the arrival (after the wagon has parked and the offload has finished cleanly).
    private(set) var arrival: Double = 0
    /// The scenery's current speed (1 = full speed).
    private(set) var speed: Double = 0
    private var lastTime: Double?
    private var lastLodgeOffset: Double?

    init(progress: Double = 0) {
        self.progress = WagonScene.clamp(progress)
    }

    /// Advances to time `t` (seconds). `stopped` holds the wagon still (cancelled or failed).
    func advance(to t: Double, target: Double, arrived: Bool, stopped: Bool) {
        // Long gaps (the window was hidden) don't make the scene leap ahead.
        let dt = lastTime.map { min(1.0 / 15, max(0, t - $0)) } ?? 0
        lastTime = t

        progress = WagonScene.easedProgress(current: progress, target: arrived ? 1 : target, dt: dt)

        // On the motion study's curve the road speed follows the progress; once the lodge is
        // nearly on screen the road moves exactly as far as the lodge does, so the lodge rides
        // the road and still lands at the parking spot at 100 % whatever the copy speed.
        let lodge = WagonScene.lodgeOffset(progress: progress)
        let curveSpeed = WagonScene.speed(progress: progress)
        var roadSpeed = curveSpeed
        if lodge.isFinite, let previous = lastLodgeOffset, previous.isFinite, dt > 0 {
            let lodgeSpeed = max(0, previous - lodge) / dt / WagonScene.baseSpeed
            let follow = 1 - WagonScene.smooth(150, 400, lodge)
            roadSpeed = WagonScene.mix(curveSpeed, min(1, lodgeSpeed), follow)
        }
        lastLodgeOffset = lodge
        // Progress arrives in bursts, so the road speed is smoothed a little (and the wagon
        // rolls to a stop rather than freezing when it is cancelled).
        let wanted = stopped || progress >= 1 ? 0 : roadSpeed
        speed += (wanted - speed) * (1 - exp(-dt / 0.25))
        if speed < 0.001 && wanted == 0 { speed = 0 }
        distance += speed * WagonScene.baseSpeed * dt

        if arrived && progress >= 1 {
            arrival = min(1, arrival + dt / WagonScene.arrivalDuration)
        }
    }

    /// Jumps straight to a state without motion (Reduce Motion): the wagon and the lodge where
    /// the progress puts them, nothing scrolling.
    func settle(progress p: Double, arrived: Bool) {
        progress = arrived ? 1 : WagonScene.clamp(p)
        arrival = arrived ? 1 : 0
        speed = 0
        lastTime = nil
        lastLodgeOffset = nil
    }

    /// A frozen frame `t` seconds into a drive at constant progress `p`, as the motion study's
    /// still mode draws it (used for screenshots and the design comparison).
    func still(progress p: Double, time t: Double, arrived: Bool) {
        progress = arrived ? 1 : WagonScene.clamp(p)
        speed = WagonScene.speed(progress: progress)
        distance = t * speed * WagonScene.baseSpeed
        arrival = progress >= 1 && arrived ? 1 : 0
        lastTime = nil
        lastLodgeOffset = nil
    }
}

/// When the wagon strip is on screen. It rises in when an offload starts and, after Done,
/// slides away before the ready row comes back (the bar keeps the finished summary meanwhile).
struct WagonStripPresence: Equatable {
    /// Seconds for the strip to rise in or sink away (ease-out).
    static let duration = 0.4
    /// How far the strip rises as it fades in (and sinks as it fades out), in points.
    static let rise = 24.0
    /// Under Reduce Motion: a plain, short crossfade instead.
    static let reducedMotionDuration = 0.2

    /// Done was pressed and the strip is on its way out.
    private(set) var dismissing = false

    func isVisible(in phase: OffloadSession.Phase) -> Bool {
        phase != .ready && !dismissing
    }

    /// Done: starts the strip's exit. Returns false (do nothing) unless the offload is
    /// finished and the strip isn't already leaving, so a double click finishes only once.
    mutating func beginDismissal(in phase: OffloadSession.Phase) -> Bool {
        guard phase == .finished, !dismissing else { return false }
        dismissing = true
        return true
    }

    /// Any phase but finished (the next card's ready row, or a new offload) resets it.
    mutating func phaseChanged(to phase: OffloadSession.Phase) {
        if phase != .finished { dismissing = false }
    }
}
