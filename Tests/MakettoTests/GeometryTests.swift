import Foundation
import Testing
#if canImport(MakettoCore)
@testable import MakettoCore
#else
@testable import Maketto
#endif

/// Rectangle `w × d` with its corner at `origin`, walls in loop order.
func rectangleWalls(_ w: Double, _ d: Double, origin: Point2D = Point2D(x: 0, z: 0)) -> [Wall] {
    let a = origin, b = origin + Point2D(x: w, z: 0)
    let c = origin + Point2D(x: w, z: d), e = origin + Point2D(x: 0, z: d)
    return [Wall(start: a, end: b), Wall(start: b, end: c), Wall(start: c, end: e), Wall(start: e, end: a)]
}

/// Shorten every wall by `gap` at both ends — what an imperfect scan returns.
func gapped(_ walls: [Wall], by gap: Double) -> [Wall] {
    walls.map { w in
        var out = w
        out.start = w.start + w.direction * gap
        out.end = w.end - w.direction * gap
        return out
    }
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

struct FloorOutlineTests {
    @Test func rectangleClosesIntoFourCorners() throws {
        let poly = try #require(FloorGeometry.outline(fromWalls: rectangleWalls(4, 3)))
        #expect(poly.count == 4)
        #expect(approx(abs(FloorGeometry.signedArea(poly)), 12))
    }

    @Test func lShapedMockHasSixCornersAndCorrectArea() throws {
        let room = RoomModel.mockLShaped
        let poly = try #require(FloorGeometry.outline(fromWalls: room.walls))
        #expect(poly.count == 6)
        #expect(approx(PlanGeometry.area(of: room), 19))
    }

    @Test func smallScanGapsStillClose() throws {
        let walls = gapped(rectangleWalls(4, 3), by: 0.03)   // 6 cm between ends
        #expect(FloorGeometry.strictOutline(fromWalls: walls, tolerance: 0.02) == nil)
        let poly = try #require(FloorGeometry.outline(fromWalls: walls))
        #expect(poly.count == 4)
    }

    @Test func danglingSpurIsIgnored() throws {
        var walls = rectangleWalls(4, 3)
        walls.append(Wall(start: Point2D(x: 4, z: 0), end: Point2D(x: 5, z: -1)))   // stray sliver
        let poly = try #require(FloorGeometry.outline(fromWalls: walls))
        #expect(poly.count == 4)
    }

    @Test func openRoomHasNoOutline() {
        let walls = Array(rectangleWalls(4, 3).dropLast())
        #expect(FloorGeometry.outline(fromWalls: walls) == nil)
    }

    @Test func twoSeparateRoomsAreNotOneOutline() {
        let walls = rectangleWalls(3, 3) + rectangleWalls(3, 3, origin: Point2D(x: 10, z: 0))
        #expect(FloorGeometry.outline(fromWalls: walls) == nil)
    }
}

struct WeldCornersTests {
    @Test func gapsWeldToTrueCorners() throws {
        let welded = FloorGeometry.weldCorners(gapped(rectangleWalls(4, 3), by: 0.04))
        #expect(welded.count == 4)
        // Every corner is now shared exactly, at the line intersection.
        let poly = try #require(FloorGeometry.strictOutline(fromWalls: welded, tolerance: 1e-6))
        #expect(poly.count == 4)
        let expected = [Point2D(x: 0, z: 0), Point2D(x: 4, z: 0), Point2D(x: 4, z: 3), Point2D(x: 0, z: 3)]
        for corner in expected {
            #expect(poly.contains { $0.distance(to: corner) < 1e-6 })
        }
    }

    @Test func farApartEndsAreLeftAlone() {
        let walls = gapped(rectangleWalls(4, 3), by: 0.3)
        let welded = FloorGeometry.weldCorners(walls, tolerance: 0.1)
        #expect(welded == walls)
    }

    @Test func shortWallNeverCollapsesIntoAPoint() {
        let walls = [Wall(start: Point2D(x: 0, z: 0), end: Point2D(x: 0.15, z: 0))]
        let welded = FloorGeometry.weldCorners(walls, tolerance: 0.2, minLength: 0.1)
        #expect(welded.count == 1)
        #expect(welded[0].length > 0.1)
    }

    @Test func sliversAreDropped() {
        var walls = rectangleWalls(4, 3)
        walls.append(Wall(start: Point2D(x: 2, z: 1), end: Point2D(x: 2.05, z: 1)))
        #expect(FloorGeometry.weldCorners(walls).count == 4)
    }
}

struct HomeGeometryTests {
    @Test func poseInverseRoundTrips() {
        let pose = Pose2D(rotation: 0.7, translation: Point2D(x: 3, z: -2))
        let p = Point2D(x: 1.25, z: 4.5)
        let back = pose.inverse.apply(to: pose.apply(to: p))
        #expect(back.distance(to: p) < 1e-9)
    }

    @Test func straighteningAlignsASkewedHome() {
        let skew = Pose2D(rotation: 0.2, translation: Point2D(x: 1, z: 1))
        let room = HomeGeometry.transform(.mock, by: skew)
        let straight = HomeGeometry.straightened([room])[0]
        for wall in straight.walls {
            #expect(PlanGeometry.offAxis(wall) < 1e-6)
        }
        // Rigid: lengths are untouched.
        #expect(zip(straight.walls, RoomModel.mock.walls).allSatisfy { approx($0.length, $1.length) })
    }

    @Test func aDiagonalWallDoesNotTiltASquareHome() {
        var room = RoomModel.mock
        room.walls.append(Wall(start: Point2D(x: 0, z: 3), end: Point2D(x: 2, z: 4.2)))   // ~31°
        #expect(HomeGeometry.straighteningPose(of: [room]) == .identity)

        let skew = Pose2D(rotation: 0.12)
        let skewed = HomeGeometry.transform(room, by: skew)
        #expect(abs(HomeGeometry.dominantAngle(of: [skewed]) - 0.12) < 1e-9)
    }

    @Test func furnitureFollowsTheFrame() {
        let pose = Pose2D(rotation: .pi / 2, translation: Point2D(x: 2, z: 0))
        let item = PlacedFurniture(name: "x", center: Point2D(x: 1, z: 0), width: 1, depth: 1)
        let moved = HomeGeometry.transform([item], by: pose)[0]
        #expect(moved.center.distance(to: Point2D(x: 2, z: 1)) < 1e-9)
        #expect(approx(moved.rotation, .pi / 2))
    }
}

struct PlanGeometryTests {
    @Test func fitKeepsAspectAndCentres() throws {
        let t = try #require(PlanGeometry.fit(.mock, in: CGSize(width: 400, height: 400), padding: 0))
        let a = t.apply(Point2D(x: 0, z: 0)), b = t.apply(Point2D(x: 4, z: 3))
        #expect(approx(Double(b.x - a.x), 400, 1e-6))          // width-limited
        #expect(approx(Double(b.y - a.y), 300, 1e-6))          // same scale on z
        #expect(approx(Double((a.y + b.y) / 2), 200, 1e-6))    // vertically centred
        let world = t.unapply(CGPoint(x: 100, y: 100))
        #expect(t.apply(world).x - 100 < 1e-9)
    }

    @Test func pointInPolygon() {
        let poly = RoomModel.mockLShaped.floorOutline!
        #expect(PlanGeometry.contains(poly, Point2D(x: 4, z: 4)))
        #expect(!PlanGeometry.contains(poly, Point2D(x: 1, z: 4)))   // the L's notch
    }

    @Test func openingSegmentSpansItsWidth() throws {
        let room = RoomModel.mockLShaped
        let door = try #require(room.openings.first { $0.type == .door })
        let seg = try #require(PlanGeometry.openingSegment(door, in: room,
                                                           interiorReference: PlanGeometry.centroid(room)))
        #expect(approx(seg.start.distance(to: seg.end), door.width))
        #expect(seg.interiorNormal.z > 0)   // wall AB is the top edge; inside is +z
    }
}

struct WholeHomeMergeTests {
    /// Two rooms sharing the wall x = 4 (same RoomPlan id in both).
    private func twoRooms() -> (RoomModel, RoomModel, Wall) {
        let shared = Wall(start: Point2D(x: 4, z: 0), end: Point2D(x: 4, z: 3))
        var a = RoomModel.mock
        a.walls[1] = shared
        var b = HomeGeometry.transform(.mock, by: Pose2D(translation: Point2D(x: 4, z: 0)))
        b.walls[3] = Wall(id: shared.id, start: shared.end, end: shared.start)   // reversed copy
        b.openings = [Opening(type: .door, onWallId: shared.id, offset: 1, width: 0.8, height: 2)]
        a.openings = [Opening(id: b.openings[0].id, type: .door, onWallId: shared.id,
                              offset: 2, width: 0.8, height: 2)]
        return (a, b, shared)
    }

    @Test func coincidingSharedWallsDrawOnce() {
        let (a, b, shared) = twoRooms()
        let merged = PlanGeometry.mergedWalls([a, b])
        #expect(merged.count == 7)
        #expect(merged.filter { $0.id == shared.id }.count == 1)
        #expect(PlanGeometry.hostedOpenings([a, b]).count == 1)
    }

    @Test func anEditedSharedWallStaysVisible() {
        var (a, b, shared) = twoRooms()
        b.walls[3].start = Point2D(x: 4.5, z: 3)        // moved in room B only
        b.walls[3].end = Point2D(x: 4.5, z: 0)
        let merged = PlanGeometry.mergedWalls([a, b])
        #expect(merged.filter { $0.id == shared.id }.count == 2)
        // Each copy keeps the door hosted on it.
        #expect(PlanGeometry.hostedOpenings([a, b]).count == 2)
    }

    @Test func scanCleanupDropsStraySliversOnly() {
        var room = RoomModel(name: "big", walls: rectangleWalls(6, 5), source: .roomplan)
        room.walls += [Wall(start: Point2D(x: 1, z: 1), end: Point2D(x: 1.5, z: 1.4)),     // sliver
                       Wall(start: Point2D(x: 3, z: 0), end: Point2D(x: 3, z: 5))]         // partition
        let cleaned = PlanGeometry.removingOffAxisOutliers([room])
        #expect(cleaned[0].walls.count == 5)
        // A genuinely angled home is untouched.
        let angled = HomeGeometry.transform(.mock, by: Pose2D(rotation: .pi / 4))
        var mixed = RoomModel(name: "m", walls: rectangleWalls(2, 2) + angled.walls + [
            Wall(start: Point2D(x: 9, z: 0), end: Point2D(x: 9, z: 1))], source: .roomplan)
        mixed.kind = nil
        #expect(PlanGeometry.removingOffAxisOutliers([mixed])[0].walls.count == mixed.walls.count)
    }
}

struct RoomNamingTests {
    @Test func duplicatesAreNumberedLargestFirst() {
        var big = RoomModel.mockLShaped; big.kind = .bedroom
        var small = RoomModel.mock; small.kind = .bedroom
        var kitchen = RoomModel.mock; kitchen.kind = .kitchen
        let named = RoomNaming.assignNames([small, big, kitchen])
        #expect(named[1].name == "Yatak Odası 1")
        #expect(named[0].name == "Yatak Odası 2")
        #expect(named[2].name == "Mutfak")
    }

    @Test func kindIsInferredFromObjects() {
        let room = RoomModel(name: "", detectedObjects: [
            DetectedObject(category: "toilet", center: Point2D(x: 0, z: 0),
                           width: 0.4, depth: 0.6, height: 0.8, rotation: 0)
        ], source: .roomplan)
        #expect(RoomNaming.effectiveKind(room) == .bathroom)
    }
}
