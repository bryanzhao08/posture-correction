import SwiftUI
import AVKit
import FormCore

struct ReplaySelection: Identifiable {
    var id:String { sessionID + ":" + String(clip.index) }
    let sessionID:String
    let clip:LocalReplay
    let url:URL
    let sport:String
    let rep:Rep
    let view:String?
}

@MainActor final class ReplayPlayer: ObservableObject {
    let player=AVPlayer()
    @Published var ready=false
    @Published var duration=1.0
    @Published var time=0.0
    @Published var shareURL:URL?
    @Published var error:String?
    private var loop:NSObjectProtocol?
    private var clock:Any?
    private var stopped=false
    private let shareFolder=FileManager.default.temporaryDirectory.appendingPathComponent("share-replay-"+UUID().uuidString)
    private var exporter:AVAssetExportSession?
    func load(_ selection:ReplaySelection) async {
        guard !ready,!stopped else { return }
        do {
            let asset=AVURLAsset(url:selection.url)
            let duration=try await asset.load(.duration)
            guard duration.seconds.isFinite,duration.seconds > 0,let track=try await asset.loadTracks(withMediaType:.video).first else { throw APIError(message:"This replay cannot be opened.") }
            let size=try await track.load(.naturalSize),transform=try await track.load(.preferredTransform)
            let item=AVPlayerItem(asset:asset)
            var composition:AVMutableVideoComposition?
            if selection.clip.mirrored {
                let video=AVMutableVideoComposition(); video.renderSize=size; video.frameDuration=CMTime(value:1,timescale:15)
                let instruction=AVMutableVideoCompositionInstruction(); instruction.timeRange=CMTimeRange(start:.zero,duration:duration)
                let layer=AVMutableVideoCompositionLayerInstruction(assetTrack:track)
                layer.setTransform(transform.concatenating(CGAffineTransform(a:-1,b:0,c:0,d:1,tx:size.width,ty:0)),at:.zero)
                instruction.layerInstructions=[layer]; video.instructions=[instruction]; composition=video
                item.videoComposition=video
            }
            guard !stopped,!Task.isCancelled else { return }
            self.duration=duration.seconds
            player.replaceCurrentItem(with:item)
            loop=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.player.seek(to:.zero); self?.player.play() }
            }
            clock=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.1,preferredTimescale:600),queue:.main) { [weak self] time in
                Task { @MainActor in if let self=self { self.time=min(self.duration,max(0,time.seconds)) } }
            }
            ready=true; player.play()
            // Share the same mirrored picture and readable caption the player shows.
            if let composition=composition {
                try FileManager.default.createDirectory(at:shareFolder,withIntermediateDirectories:true)
                let url=shareFolder.appendingPathComponent("Rep-\(selection.clip.index).mp4")
                guard let export=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetMediumQuality) else { throw APIError(message:"Cannot prepare replay sharing.") }
                exporter=export; export.outputURL=url; export.outputFileType = .mp4; export.videoComposition=composition
                await withCheckedContinuation { continuation in export.exportAsynchronously { continuation.resume() } }
                guard !stopped,!Task.isCancelled else { try? FileManager.default.removeItem(at:shareFolder); return }
                guard export.status == .completed else { throw export.error ?? APIError(message:"Cannot prepare replay sharing.") }
                shareURL=url
            } else { shareURL=selection.url }
        } catch { if !stopped { self.error=error.localizedDescription } }
    }
    func seek(_ value:Double) { time=value; player.seek(to:CMTime(seconds:value,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) }
    func freeze() { player.pause(); seek(max(0,duration-0.8)) }
    func stop() {
        stopped=true; player.pause(); exporter?.cancelExport()
        if let loop=loop { NotificationCenter.default.removeObserver(loop); self.loop=nil }
        if let clock=clock { player.removeTimeObserver(clock); self.clock=nil }
        player.replaceCurrentItem(with:nil)
        try? FileManager.default.removeItem(at:shareFolder)
    }
}

struct ReplayView: View {
    let selection:ReplaySelection
    @StateObject private var model=ReplayPlayer()
    @EnvironmentObject private var state:AppState
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    VideoPlayer(player:model.player).aspectRatio(9.0/16.0,contentMode:.fit).frame(maxHeight:480)
                        .accessibilityIdentifier("replay.video")
                    if model.ready {
                        HStack {
                            Button("Play / pause") { if model.player.rate == 0 { model.player.play() } else { model.player.pause() } }.accessibilityIdentifier("replay.play")
                            Spacer()
                            Button("View the fix") { model.freeze() }.accessibilityIdentifier("replay.freeze")
                        }.buttonStyle(.bordered)
                        Slider(value:Binding(get:{ model.time },set:{ model.seek($0) }),in:0...model.duration)
                            .accessibilityLabel("Replay position").accessibilityIdentifier("replay.scrub")
                        Text("Rep \(selection.clip.index) · \(Display.score(selection.rep.score)) · \(selection.clip.shortLabel)").font(.headline)
                        Text("Your swing (white) vs the fix (cyan)").font(.caption).foregroundStyle(.secondary)
                    } else { ProgressView("Opening replay…") }
                    if let error=model.error { ErrorNotice(message:error) }
                    ForEach(Array(selection.rep.cues.enumerated()),id:\.offset) { _,cue in
                        ReplayCue(text:cue,sport:selection.sport,profile:state.profiles?.sports[selection.sport]?.effective(for:selection.view))
                    }
                }.padding()
            }.navigationTitle("Rep \(selection.clip.index) replay").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("replay.close") }
                    ToolbarItem(placement:.primaryAction) {
                        if let url=model.shareURL { ShareLink(item:url) { Label("Share",systemImage:"square.and.arrow.up") }.accessibilityIdentifier("replay.share") }
                    }
                }
        }.modifier(DemoPresentation())
            .task { await model.load(selection) }
            .onDisappear { if DemoOffers.shared.isPresenting { model.player.pause() } else { model.stop() } }
            .onAppear { if model.ready { model.player.play() } }
    }
}

private struct ReplayCue:View {
    let text:String
    let sport:String
    let profile:SportProfile?
    @EnvironmentObject private var presenter:DemoPresenter
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(text)
            if let profile=profile,profile.metric(forCue:text).flatMap({ correctionEvent(analyzer:profile.analyzer,metric:$0.id) }) == nil,let cue=DemoCatalog.entry(text,sport:sport,setup:false) {
                Text(cue.meaning).font(.subheadline).foregroundStyle(.secondary)
                Button("Show me") { presenter.cue=cue; DemoOffers.shared.isPresenting=true }
                    .buttonStyle(.bordered).accessibilityIdentifier("replay.demo."+cue.key)
            }
        }
    }
}
