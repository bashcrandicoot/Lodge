import XCTest
@testable import Lodge

/// The wagon strip's progress → scene maths, checked against Maddy's motion study
/// (`wagon-progress.html`, still mode at t = 2 s) and the Figma scenes.
@MainActor
final class WagonSceneTests: XCTestCase {
    private let accuracy = 0.01

    func testWagonDrivesFromTheLeftEdgeToTheParkingSpot() {
        XCTAssertEqual(WagonScene.wagonX(progress: 0), 18, accuracy: accuracy)
        XCTAssertEqual(WagonScene.wagonX(progress: 0.62), 528.88, accuracy: accuracy)
        XCTAssertEqual(WagonScene.wagonX(progress: 0.88), 743.12, accuracy: accuracy)
        XCTAssertEqual(WagonScene.wagonX(progress: 0.95), 800.8, accuracy: accuracy)
        XCTAssertEqual(WagonScene.wagonX(progress: 1), 842, accuracy: accuracy)
        // Out-of-range progress is clamped.
        XCTAssertEqual(WagonScene.wagonX(progress: 1.4), 842, accuracy: accuracy)
        XCTAssertEqual(WagonScene.wagonX(progress: -0.2), 18, accuracy: accuracy)
    }

    func testParkingSpotStaysAnchoredToTheRightEdge() {
        XCTAssertEqual(WagonScene.parkX(width: 1060), 842, accuracy: accuracy)
        XCTAssertEqual(WagonScene.parkX(width: 1400), 1182, accuracy: accuracy)
        XCTAssertEqual(WagonScene.wagonX(progress: 1, width: 940), 722, accuracy: accuracy)
    }

    func testTrailEndsUnderTheWagon() {
        XCTAssertEqual(WagonScene.trailWidth(progress: 0.62), 538.88, accuracy: accuracy)
    }

    func testSceneryKeepsFullSpeedThenSlowsToAStop() {
        XCTAssertEqual(WagonScene.speed(progress: 0), 1)
        XCTAssertEqual(WagonScene.speed(progress: 0.62), 1)
        XCTAssertEqual(WagonScene.speed(progress: 0.85), 1)
        XCTAssertEqual(WagonScene.speed(progress: 0.88), 0.896, accuracy: 0.001)
        XCTAssertEqual(WagonScene.speed(progress: 0.95), 0.2593, accuracy: 0.001)
        XCTAssertEqual(WagonScene.speed(progress: 1), 0)
        var previous = 1.0
        for step in 0...100 {
            let speed = WagonScene.speed(progress: Double(step) / 100)
            XCTAssertLessThanOrEqual(speed, previous + 1e-12)
            previous = speed
        }
    }

    func testLodgeComesDownTheRoadAndLandsAtOneHundredPercent() {
        XCTAssertEqual(WagonScene.lodgeOffset(progress: 0.62), .infinity)
        XCTAssertEqual(WagonScene.lodgeOffset(progress: 0.72), .infinity)
        XCTAssertEqual(WagonScene.lodgeOffset(progress: 0.88), 273.2, accuracy: 0.5)
        XCTAssertEqual(WagonScene.lodgeOffset(progress: 0.95), 43.21, accuracy: 0.5)
        XCTAssertEqual(WagonScene.lodgeOffset(progress: 1), 0)
        XCTAssertEqual(SlowdownCurve.shared.finalDistance, 848.6, accuracy: 0.5)

        // Hidden until it is nearly on screen, then always visible.
        XCTAssertFalse(WagonScene.isLodgeVisible(offset: WagonScene.lodgeOffset(progress: 0.62)))
        XCTAssertFalse(WagonScene.isLodgeVisible(offset: WagonScene.lodgeOffset(progress: 0.88)))
        XCTAssertTrue(WagonScene.isLodgeVisible(offset: WagonScene.lodgeOffset(progress: 0.95)))
        XCTAssertTrue(WagonScene.isLodgeVisible(offset: WagonScene.lodgeOffset(progress: 1)))

        // It only ever gets closer.
        var previous = Double.infinity
        for step in 0...280 {
            let offset = WagonScene.lodgeOffset(progress: 0.72 + Double(step) / 1000)
            XCTAssertLessThanOrEqual(offset, previous)
            previous = offset
        }
    }

    func testSlowdownCurveInvertsCleanly() {
        for p in stride(from: 0.73, through: 0.99, by: 0.02) {
            XCTAssertEqual(SlowdownCurve.progress(atTime: SlowdownCurve.time(atProgress: p)), p, accuracy: 1e-9)
        }
        XCTAssertEqual(SlowdownCurve.progress(atTime: 0), 0.72, accuracy: 1e-12)
        XCTAssertEqual(SlowdownCurve.progress(atTime: SlowdownCurve.duration), 1)
    }

    func testParallaxLayersAtTheDesignFrame() {
        // 62 % at t = 2 s: 660 pt of road.
        let distance = 2 * WagonScene.speed(progress: 0.62) * WagonScene.baseSpeed
        XCTAssertEqual(distance, 660, accuracy: accuracy)
        XCTAssertEqual(WagonScene.layerOffset(distance: distance, speed: WagonScene.Layer.farMountains), -23.76, accuracy: accuracy)
        XCTAssertEqual(WagonScene.layerOffset(distance: distance, speed: WagonScene.Layer.hills), -52.8, accuracy: accuracy)
        XCTAssertEqual(WagonScene.layerOffset(distance: distance, speed: WagonScene.Layer.pines), -132, accuracy: accuracy)
        XCTAssertEqual(WagonScene.layerOffset(distance: distance, speed: WagonScene.Layer.foreground), -260, accuracy: accuracy)
        XCTAssertEqual(WagonScene.layerOffset(distance: 0, speed: 1), 0)
        // Always within one tile to the left.
        for distance in stride(from: 0.0, through: 5000, by: 37.3) {
            let offset = WagonScene.layerOffset(distance: distance, speed: 2, period: 28)
            XCTAssertLessThanOrEqual(offset, 0)
            XCTAssertGreaterThan(offset, -28)
        }
    }

    func testWheelsRollWithTheRoad() {
        XCTAssertEqual(WagonScene.wheelAngle(distance: 660), 330, accuracy: accuracy)
        XCTAssertEqual(WagonScene.wheelAngle(distance: 2 * 0.896 * 330), 94.08, accuracy: 0.05)
        XCTAssertEqual(WagonScene.wheelAngle(distance: 0), 0)
    }

    func testForegroundBlurFollowsSpeed() {
        XCTAssertEqual(WagonScene.foregroundBlur(speed: WagonScene.speed(progress: 0.62)), 2.4, accuracy: accuracy)
        XCTAssertEqual(WagonScene.foregroundBlur(speed: WagonScene.speed(progress: 0.88)), 2.15, accuracy: accuracy)
        XCTAssertEqual(WagonScene.foregroundBlur(speed: WagonScene.speed(progress: 0.95)), 0.62, accuracy: accuracy)
        XCTAssertEqual(WagonScene.foregroundBlur(speed: 0), 0)
    }

    func testHorizontalBlurKernelIsANormalisedGaussian() {
        let kernel = WagonScene.horizontalBlurKernel(sigma: 2.4, taps: 9)
        XCTAssertEqual(kernel.count, 9)
        XCTAssertEqual(kernel.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertEqual(kernel.first!.offset, -6, accuracy: 1e-9)   // ±2.5σ
        XCTAssertEqual(kernel.last!.offset, 6, accuracy: 1e-9)
        XCTAssertEqual(kernel[4].offset, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(kernel[4].weight, kernel[3].weight)
        XCTAssertEqual(kernel[3].weight, kernel[5].weight, accuracy: 1e-12)
        // No blur when parked.
        XCTAssertEqual(WagonScene.horizontalBlurKernel(sigma: 0).count, 1)
    }

    func testArrivalEaseThresholds() {
        XCTAssertEqual(WagonScene.arrivalEase(0), 0)
        XCTAssertEqual(WagonScene.arrivalEase(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(WagonScene.arrivalEase(1), 1)
        XCTAssertLessThan(WagonScene.arrivalEase(0.1), 0.1)
    }

    func testEasedProgressNeverGoesBackAndConverges() {
        var shown = 0.3
        XCTAssertEqual(WagonScene.easedProgress(current: shown, target: 0.2, dt: 1), 0.3)
        var previous = shown
        for _ in 0..<240 {
            shown = WagonScene.easedProgress(current: shown, target: 0.62, dt: 1.0 / 60)
            XCTAssertGreaterThanOrEqual(shown, previous)
            XCTAssertLessThanOrEqual(shown, 0.62)
            previous = shown
        }
        XCTAssertEqual(shown, 0.62)
    }

    func testDriverParksThenPlaysTheArrival() {
        let driver = WagonDriver(progress: 0.95)
        var t = 0.0
        driver.advance(to: t, target: 1, arrived: false, stopped: false)
        // Reaching 100 % before verification finishes: parked, waiting, lodge still dark.
        for _ in 0..<600 {
            t += 1.0 / 60
            driver.advance(to: t, target: 1, arrived: false, stopped: false)
        }
        XCTAssertEqual(driver.progress, 1)
        XCTAssertEqual(driver.speed, 0)
        XCTAssertEqual(driver.arrival, 0)
        // Verified: the lodge lights up over 1.4 s.
        for _ in 0..<42 {
            t += 1.0 / 60
            driver.advance(to: t, target: 1, arrived: true, stopped: false)
        }
        XCTAssertEqual(driver.arrival, 0.5, accuracy: 0.02)
        for _ in 0..<60 {
            t += 1.0 / 60
            driver.advance(to: t, target: 1, arrived: true, stopped: false)
        }
        XCTAssertEqual(driver.arrival, 1)
    }

    func testDriverScrollsWhileCopyingAndStopsWhenCancelled() {
        let driver = WagonDriver(progress: 0.3)
        var t = 0.0
        for _ in 0..<120 {
            driver.advance(to: t, target: 0.31, arrived: false, stopped: false)
            t += 1.0 / 60
        }
        XCTAssertGreaterThan(driver.distance, 500)
        XCTAssertEqual(driver.speed, 1, accuracy: 0.01)
        for _ in 0..<120 {
            driver.advance(to: t, target: 0.31, arrived: false, stopped: true)
            t += 1.0 / 60
        }
        XCTAssertEqual(driver.speed, 0)
        XCTAssertEqual(driver.arrival, 0)
        XCTAssertLessThan(driver.progress, 1)
    }

    func testDriverDoesNotLeapAfterTheWindowWasHidden() {
        let driver = WagonDriver(progress: 0.3)
        driver.advance(to: 0, target: 0.3, arrived: false, stopped: false)
        driver.advance(to: 1.0 / 60, target: 0.3, arrived: false, stopped: false)
        let before = driver.distance
        driver.advance(to: 600, target: 0.3, arrived: false, stopped: false)
        XCTAssertLessThanOrEqual(driver.distance - before, WagonScene.baseSpeed / 15 + 1e-9)
    }

    func testStillFrameMatchesTheMotionStudy() {
        let driver = WagonDriver()
        driver.still(progress: 0.62, time: 2, arrived: false)
        XCTAssertEqual(driver.distance, 660, accuracy: accuracy)
        XCTAssertEqual(driver.arrival, 0)
        driver.still(progress: 1, time: 2.4, arrived: true)
        XCTAssertEqual(driver.distance, 0)
        XCTAssertEqual(driver.arrival, 1)
        driver.settle(progress: 0.5, arrived: false)
        XCTAssertEqual(driver.speed, 0)
        XCTAssertEqual(driver.progress, 0.5)
    }

    func testParticles() {
        let dust = WagonScene.dust(wagonX: 528.88, speed: 1, time: 2)
        XCTAssertEqual(dust.count, 5)
        XCTAssertTrue(dust.allSatisfy { $0.opacity >= 0 && $0.opacity <= 0.26 })
        XCTAssertTrue(WagonScene.dust(wagonX: 0, speed: 0, time: 2).allSatisfy { $0.opacity == 0 })
        XCTAssertEqual(WagonScene.smoke(arrival: 1, time: 3).count, 6)
        XCTAssertEqual(WagonScene.fireflies.count, 6)
        let fly = WagonScene.firefly(0, time: 0)
        XCTAssertEqual(fly.x, 944, accuracy: accuracy)
        XCTAssertEqual(fly.y, 81, accuracy: accuracy)
    }
}

/// When the wagon strip shows: in on Offload, out on Done before the ready row returns.
@MainActor
final class WagonStripPresenceTests: XCTestCase {
    func testStripShowsWhileRunningAndFinished() {
        let strip = WagonStripPresence()
        XCTAssertFalse(strip.isVisible(in: .ready))
        XCTAssertTrue(strip.isVisible(in: .running))
        XCTAssertTrue(strip.isVisible(in: .finished))
    }

    func testDoneHidesTheStripWhileTheSummaryStays() {
        var strip = WagonStripPresence()
        XCTAssertTrue(strip.beginDismissal(in: .finished))
        XCTAssertFalse(strip.isVisible(in: .finished))
        // A second click (or Return) while it's leaving does nothing.
        XCTAssertFalse(strip.beginDismissal(in: .finished))
    }

    func testDoneOnlyWorksOnceTheOffloadHasFinished() {
        var strip = WagonStripPresence()
        XCTAssertFalse(strip.beginDismissal(in: .running))
        XCTAssertFalse(strip.beginDismissal(in: .ready))
        XCTAssertTrue(strip.isVisible(in: .running))
    }

    func testTheNextOffloadShowsTheStripAgain() {
        var strip = WagonStripPresence()
        _ = strip.beginDismissal(in: .finished)
        strip.phaseChanged(to: .finished)
        XCTAssertFalse(strip.isVisible(in: .finished))
        strip.phaseChanged(to: .ready)
        XCTAssertFalse(strip.isVisible(in: .ready))
        strip.phaseChanged(to: .running)
        XCTAssertTrue(strip.isVisible(in: .running))
        XCTAssertEqual(strip, WagonStripPresence())
    }

    func testTimingMatchesTheBrief() {
        XCTAssertGreaterThanOrEqual(WagonStripPresence.duration, 0.35)
        XCTAssertLessThanOrEqual(WagonStripPresence.duration, 0.45)
        XCTAssertEqual(WagonStripPresence.rise, 24)
        XCTAssertLessThan(WagonStripPresence.reducedMotionDuration, WagonStripPresence.duration)
    }
}
