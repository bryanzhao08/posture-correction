import XCTest
import FormCore

final class StrokeEstimateTests: XCTestCase {
    private func prediction(_ label: String, _ probability: Double, spin: String = "slice", spinP: Double = 0.6) -> StrokePrediction {
        ["coarse":StrokeTaskPrediction(label:label,probs:[label:probability]),
         "groundstroke_spin":StrokeTaskPrediction(label:spin,probs:[spin:spinP]),
         "serve_type":StrokeTaskPrediction(label:"kick",probs:["kick":1])]
    }
    func testConfidenceAndExperimentalOutputPolicy() {
        XCTAssertNil(StrokeEstimate.display(prediction("forehand",0.599999)))
        XCTAssertEqual(StrokeEstimate.display(prediction("forehand",0.6))?.text,"Forehand · slice · estimate")
        XCTAssertEqual(StrokeEstimate.display(prediction("backhand_one",0.6,spin:"flat_topspin"))?.text,"One-handed backhand · topspin/flat · estimate")
        XCTAssertEqual(StrokeEstimate.display(prediction("backhand_two",0.6,spinP:0.599999))?.text,"Two-handed backhand · estimate")
        XCTAssertEqual(StrokeEstimate.display(prediction("serve",0.6))?.text,"Serve · estimate")
        for weak in ["volley","smash"] {
            XCTAssertNil(StrokeEstimate.display(prediction(weak,0.749999)))
            XCTAssertNotNil(StrokeEstimate.display(prediction(weak,0.75)))
        }
    }
    func testEstimatesPersistLocallyButNeverEnterUpload() throws {
        let repJSON = #"{"t_start":0,"t_end":1,"type":"forehand","events":{},"metrics":{},"scores":{},"score":90,"cues":[],"peak_speed":5}"#
        var rep = try JSONDecoder().decode(Rep.self,from:Data(repJSON.utf8))
        XCTAssertNil(rep.strokeEstimate, "Older saved reps still decode")
        rep.strokeEstimate = prediction("forehand",0.9)
        let summaryJSON = #"{"sport":"tennis","rep_count":1,"rejected":{},"types":{"forehand":1},"score":90,"form_score":90,"consistency":null,"metrics":{},"top_cues":[],"active_s":1,"passive_s":0}"#
        let summary = try JSONDecoder().decode(SessionSummary.self,from:Data(summaryJSON.utf8))
        let payload = SessionIn(clientID:UUID().uuidString,sport:"tennis",handedness:.right,startedAt:"2026-10-14T00:00:00Z",durationS:1,summary:summary,reps:[rep],appVersion:"test",device:"simulator")
        let local = try JSONEncoder().encode(payload)
        XCTAssertTrue(String(decoding:local,as:UTF8.self).contains("stroke_estimate"))
        XCTAssertNotNil(try JSONDecoder().decode(SessionIn.self,from:local).reps[0].strokeEstimate)
        let upload = try JSONEncoder().encode(payload.forUpload)
        XCTAssertFalse(String(decoding:upload,as:UTF8.self).contains("stroke_estimate"))
        XCTAssertNotNil(payload.reps[0].strokeEstimate, "Stripping an upload must not mutate local data")
        var two = rep, one = rep, serve = rep
        two.strokeEstimate = prediction("backhand_two",0.9)
        one.strokeEstimate = prediction("backhand_one",0.9)
        serve.strokeEstimate = prediction("serve",0.9)
        XCTAssertEqual(StrokeEstimate.counts([rep,one,two,serve]),"1 forehand · 2 backhands · 1 serve")
    }

}
