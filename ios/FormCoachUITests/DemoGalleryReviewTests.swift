import XCTest
import simd

/// SLOW visual audit: opens all 40 entries in the DEBUG Settings gallery and attaches 80 PNGs.
/// Run alone with -only-testing:FormCoachUITests/DemoGalleryReviewTests when reviewing artwork.
final class DemoGalleryReviewTests:XCTestCase {
    func testSlowReviewEveryWrongAndCorrectKeyMoment() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-uiTesting","-resetTestAccount","-demoGallery","-backendURL","http://127.0.0.1:18004"]
        app.launch()
        let gallery=app.buttons["demo.gallery"]
        for _ in 0..<12 { if gallery.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(gallery.waitForExistence(timeout:10)); gallery.tap()
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"cue_catalog",withExtension:"json"))
        let entries=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [[String:Any]])
        let search=app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:10),app.debugDescription)
        var previousKey=""
        let onlyKey=ProcessInfo.processInfo.environment["FORMCOACH_GALLERY_REVIEW_KEY"]
        var reviewed=0
        for sport in ["basketball","golf","pickleball","tennis"] {
            let keys=["setup."+sport]+entries.filter { $0["sport"] as? String == sport }.compactMap { $0["key"] as? String }.sorted()
            for key in keys where onlyKey == nil || onlyKey == key {
                search.tap()
                if !previousKey.isEmpty {
                    let clear=search.buttons["Clear text"]
                    XCTAssertTrue(clear.waitForExistence(timeout:5)); clear.tap()
                }
                search.typeText(key); previousKey=key
                let button=app.buttons["gallery."+key]
                XCTAssertTrue(button.waitForExistence(timeout:10),key)
                XCTAssertTrue(button.exists,key); button.tap()
                XCTAssertTrue(app.buttons["hologram.close"].waitForExistence(timeout:10),key)
                app.buttons["hologram.keyMoment"].tap()
                for mode in ["Wrong","Correct"] {
                    app.buttons[mode].tap()
                    usleep(350_000)
                    let attachment=XCTAttachment(screenshot:app.screenshot())
                    attachment.name=key+"-"+mode.lowercased()+".png"; attachment.lifetime = .keepAlways
                    add(attachment)
                }
                app.buttons["hologram.close"].tap()
                app.activate()
                XCTAssertTrue(search.waitForExistence(timeout:10),app.debugDescription)
                reviewed += 1
            }
        }
        XCTAssertEqual(reviewed,onlyKey == nil ? 40 : 1)
    }
}

final class DemoAnatomyTests:XCTestCase {
    func testOverheadArmIsFullyExtendedAtContact() {
        for base in [BaseMotion.tennisServe,.pickleballOverhead] {
            let pose=DemoMotion(base:base,parameters:[:]).frames[2]
            let s=DemoSkeleton(p:pose,base:base)
            let upper=simd_normalize(s.points["r_shoulder"]!-s.points["r_elbow"]!)
            let lower=simd_normalize(s.points["r_wrist"]!-s.points["r_elbow"]!)
            let bend=180-acos(max(-1,min(1,simd_dot(upper,lower))))*180/Float.pi
            XCTAssertEqual(bend,5,accuracy:1)
        }
    }
    func testHeadSwayKeepsTheNeckLengthAndMovesTheShoulders() {
        let good=DemoMotion(base:.golfSwing,parameters:[:]).frames[1]
        var bad=good; bad.headX=0.32
        let correct=DemoSkeleton(p:good,base:.golfSwing), wrong=DemoSkeleton(p:bad,base:.golfSwing)
        XCTAssertEqual(simd_distance(wrong.points["chest"]!,wrong.points["head"]!),0.25,accuracy:0.001)
        XCTAssertEqual(wrong.points["head"]!.x-correct.points["head"]!.x,0.32,accuracy:0.001)
        XCTAssertGreaterThan(wrong.points["chest"]!.x-correct.points["chest"]!.x,0.2)
    }
    func testCorrectArmLengthsAndStableGolfHead() {
        for base in BaseMotion.allCases {
            let motion=DemoMotion(base:base,parameters:[:])
            for pose in motion.frames {
                let skeleton=DemoSkeleton(p:pose,base:base)
                for side in ["l","r"] {
                    XCTAssertEqual(simd_distance(skeleton.points[side+"_elbow"]!,skeleton.points[side+"_wrist"]!),0.27,accuracy:0.001,"\(base) \(side)")
                }
            }
        }
        let golf=DemoMotion(base:.golfSwing,parameters:[:])
        let address=DemoSkeleton(p:golf.frames[0],base:.golfSwing)
        let top=DemoSkeleton(p:golf.frames[1],base:.golfSwing)
        XCTAssertEqual(simd_distance(address.points["head"]!,top.points["head"]!),0,accuracy:0.001)
    }
    func testGolfGripAnchorsAndAdultChainsAcrossSwing() {
        let motion=DemoMotion(base:.golfSwing,parameters:[:])
        for t in stride(from:Float(0),through:motion.duration,by:0.02) {
            let p=motion.sample(t),s=DemoSkeleton(p:p,base:.golfSwing)
            XCTAssertEqual(simd_distance(s.points["l_wrist"]!,s.grip),0,accuracy:0.0001)
            XCTAssertEqual(simd_distance(s.points["r_wrist"]!,s.grip),0.075,accuracy:0.0001)
            for side in ["l","r"] {
                XCTAssertEqual(s.points[side+"_ankle"]!.x,side == "l" ? -0.224 : 0.224,accuracy:0.001)
                XCTAssertEqual(simd_distance(s.points[side+"_shoulder"]!,s.points[side+"_elbow"]!),0.342,accuracy:0.001)
            }
        }
        XCTAssertEqual(motion.frames[1].shoulderTurn,90)
        XCTAssertEqual(motion.frames[1].hipTurn,45)
        XCTAssertEqual(motion.frames[1].spine,38)
        XCTAssertEqual(motion.frames[1].shaft.y,0.02)
    }
}
