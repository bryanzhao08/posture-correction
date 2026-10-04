import XCTest
import CoreVideo
import FormCore

final class OrangeMarkerTests: XCTestCase {
    func testBGRAComponentsHaveTopLeftCoordinates() throws {
        var optional: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,128,128,kCVPixelFormatType_32BGRA,nil,&optional),kCVReturnSuccess)
        let buffer = try XCTUnwrap(optional)
        CVPixelBufferLockBaseAddress(buffer,[])
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        memset(bytes,0,stride*128)
        // Orange H=25°, S=1, V=1; two separate blobs, plus one tiny rejected speck.
        for (x,y) in [(24,36),(80,88)] {
            for dy in 0..<12 { for dx in 0..<12 {
                let i = (y+dy)*stride+(x+dx)*4
                bytes[i] = 0; bytes[i+1] = 106; bytes[i+2] = 255; bytes[i+3] = 255
            } }
        }
        bytes[4*stride+4*4+1] = 106; bytes[4*stride+4*4+2] = 255
        CVPixelBufferUnlockBaseAddress(buffer,[])
        let tracker = OrangeMarkerTracker(names: [],sport: "golf",handedness: .right)
        let points = tracker.detect(buffer)
        XCTAssertEqual(points.count,2)
        XCTAssertEqual(points[0].x,28.5/128,accuracy: 0.001)
        XCTAssertEqual(points[0].y,40.5/128,accuracy: 0.001)
        XCTAssertEqual(points[1].x,84.5/128,accuracy: 0.001)
    }
    func testOnlyLowConfidenceLeadWristIsReplaced() {
        let names = ["l_elbow","l_wrist","r_wrist"]
        let tracker = OrangeMarkerTracker(names: names,sport: "golf",handedness: .right)
        let elbow = JointObservation(x: 0.3,y: 0.4,confidence: 0.9)
        let wrist = JointObservation(x: 0.4,y: 0.5,confidence: 0.9)
        let opposite = JointObservation(x: 0.8,y: 0.5,confidence: 0.9)
        _ = tracker.substitute(joints: [elbow,wrist,opposite],markers: [],t: 1)
        let markers = [MarkerPoint(x: 0.42,y: 0.51),MarkerPoint(x: 0.6,y: 0.7)]
        let result = tracker.substitute(joints: [elbow,nil,opposite],markers: markers,t: 1.1)
        XCTAssertEqual(result[1]?.confidence,0.6)
        XCTAssertEqual(result[1]?.x,0.42)
        XCTAssertEqual(result[0]?.confidence,0.9)
        XCTAssertEqual(result[2]?.x,opposite.x)
        XCTAssertEqual(tracker.implement,markers[1])
        let distant = tracker.substitute(joints: [elbow,nil,opposite],markers: [MarkerPoint(x: 0.9,y: 0.9)],t: 1.2)
        XCTAssertNil(distant[1])
        let confident = tracker.substitute(joints: [elbow,wrist,opposite],markers: markers,t: 1.3)
        XCTAssertEqual(confident[1]?.x,wrist.x)
        tracker.reset()
        XCTAssertNil(tracker.substitute(joints: [elbow,nil,opposite],markers: markers,t: 1.4)[1])
    }
    func testDominantWristExtrapolationAndStaleHistory() {
        let tracker = OrangeMarkerTracker(names: ["r_elbow","r_wrist","l_wrist"],sport: "tennis",handedness: .right)
        let left = JointObservation(x: 0.7,y: 0.5,confidence: 0.2)
        _ = tracker.substitute(joints: [JointObservation(x: 0.2,y: 0.3,confidence: 0.9),
            JointObservation(x: 0.3,y: 0.4,confidence: 0.9),left],markers: [],t: 1)
        let movedElbow = JointObservation(x: 0.4,y: 0.3,confidence: 0.9)
        let marker = MarkerPoint(x: 0.51,y: 0.4)
        let result = tracker.substitute(joints: [movedElbow,nil,left],markers: [marker],t: 1.2)
        XCTAssertEqual(result[1]?.x,marker.x)
        XCTAssertEqual(result[2]?.confidence,0.2)
        XCTAssertNil(tracker.substitute(joints: [movedElbow,nil,left],markers: [marker],t: 3)[1])
    }

}
