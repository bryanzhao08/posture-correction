import AVFoundation
import UIKit
import CoreImage
import FormCore

struct CapturedReplay {
    let index: Int
    let cue: String
    let shortLabel: String
    let mirrored: Bool
    let url: URL
    let thumbnail: Data
}

/// Source-queue ring, with serial off-camera encoding. JPEG ring + two bounded jobs stay below 20 MB.
final class ReplayRecorder {
    private let encoder = DispatchQueue(label: "com.formcoach.replay-writer", qos: .utility)
    private let group = DispatchGroup()
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates:false])
    private var frames: [FeedbackFrame] = []
    private var pending: [RepCard] = []
    private var lastTime = -Double.infinity
    private var submitted = 0
    private var jobs = 0
    private var results: [CapturedReplay] = []
    private var cancelled = false
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("replay-" + UUID().uuidString)
    init() { try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true) }
    func append(t:Double,joints:[JointObservation?],names:[String],aspect:Double,mirrored:Bool,buffer:CVPixelBuffer?) {
        guard t-lastTime >= 0.063 else { return }; lastTime=t
        var pose: [String:Point] = [:]
        for (name,j) in zip(names,joints) { if let j=j,j.confidence >= 0.3 { pose[name]=Point(x:j.x*aspect,y:j.y) } }
        var data:Data?
        if let buffer=buffer {
            let image=CIImage(cvPixelBuffer:buffer),scale=min(1,480/image.extent.height)
            let scaled=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            if let cg=context.createCGImage(scaled,from:scaled.extent) { data=UIImage(cgImage:cg).jpegData(compressionQuality:0.55) }
        }
        frames.append(FeedbackFrame(t:t,pose:pose,torso:0.2,aspect:aspect,mirrored:mirrored,imageData:data))
        frames.removeAll { $0.t < t-4.3 }
        // Explicit byte cap also covers unexpectedly noisy camera frames.
        while frames.reduce(0,{ $0+($1.imageData?.count ?? 0) }) > 4_000_000 { frames.removeFirst() }
        let ready=pending.filter { t >= $0.rep.tEnd+0.4 }
        pending.removeAll { t >= $0.rep.tEnd+0.4 }
        for card in ready { submit(card) }
    }
    func add(_ card:RepCard) {
        guard card.corrected != nil,submitted+pending.count < 20 else { return }
        pending.append(card)
    }
    private func submit(_ card:RepCard) {
        let start=card.rep.tStart-0.4,end=card.rep.tEnd+0.4
        guard let first=frames.first,let last=frames.last,first.t <= start+0.075,last.t >= end-0.075 else { return }
        let captured=frames.filter { $0.t >= start-0.075 && $0.t <= end+0.075 }
        guard captured.count >= 2 else { return }
        lock.lock(); let allowed = jobs < 2 && !cancelled; if allowed { jobs+=1 }; lock.unlock()
        guard allowed else { return }; submitted+=1; group.enter()
        encoder.async { [self] in
            defer { lock.lock(); jobs-=1; lock.unlock(); group.leave() }
            do {
                let url=folder.appendingPathComponent("rep-\(card.index).mp4")
                try Self.write(frames:captured,card:card,start:start,end:end,url:url)
                let result=CapturedReplay(index:card.index,cue:card.cue,shortLabel:card.shortLabel,mirrored:card.frame.mirrored,url:url,thumbnail:FeedbackDrawing.image(card,height:160).jpegData(compressionQuality:0.6) ?? Data())
                lock.lock(); if !cancelled { results.append(result) }; let remove=cancelled; lock.unlock()
                if remove { try? FileManager.default.removeItem(at:url) }
            } catch { NSLog("Replay skipped: %@",error.localizedDescription) }
        }
    }
    func finish(_ completion:@escaping ([CapturedReplay])->Void) {
        pending.removeAll(); frames.removeAll()
        group.notify(queue:encoder) { [self] in lock.lock(); let clips=results.sorted { $0.index < $1.index }; lock.unlock(); completion(clips) }
    }
    func discard() {
        frames.removeAll(); pending.removeAll(); lock.lock(); cancelled=true; lock.unlock()
        group.notify(queue:encoder) { [folder] in try? FileManager.default.removeItem(at:folder) }
    }
    func reset() { frames.removeAll(); pending.removeAll(); lastTime = -Double.infinity }
    private static func write(frames:[FeedbackFrame],card:RepCard,start:Double,end:Double,url:URL) throws {
        let width=max(2,Int(480*card.frame.aspect)/2*2),height=480
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:500_000]])
        input.expectsMediaDataInRealTime=false
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        writer.add(input); guard writer.startWriting() else { throw writer.error ?? APIError(message:"Replay writer could not start.") }
        writer.startSession(atSourceTime:.zero)
        let motionCount=max(1,Int(ceil((end-start)*15))),count=motionCount+23
        let size=CGSize(width:width,height:height)
        for i in 0..<count {
            try autoreleasepool {
                let deadline=Date().addingTimeInterval(30)
                while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline { Thread.sleep(forTimeInterval:0.005) }
                guard input.isReadyForMoreMediaData,let pool=adaptor.pixelBufferPool else { throw writer.error ?? APIError(message:"Replay encoding timed out.") }
                var pixel:CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel)
                guard let pixel=pixel else { throw APIError(message:"Replay frame allocation failed.") }
                CVPixelBufferLockBaseAddress(pixel,[]); defer { CVPixelBufferUnlockBaseAddress(pixel,[]) }
                guard let ctx=CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw APIError(message:"Replay drawing failed.") }
                ctx.translateBy(x:0,y:CGFloat(height)); ctx.scaleBy(x:1,y:-1)
                let freeze=i >= motionCount,time=start+Double(i)/15
                let frame=freeze ? card.frame : frames.min { abs($0.t-time) < abs($1.t-time) }!
                UIGraphicsPushContext(ctx); defer { UIGraphicsPopContext() }
                UIColor(white:0.06,alpha:1).setFill(); ctx.fill(CGRect(origin:.zero,size:size))
                let picture=CGSize(width:min(CGFloat(width),CGFloat(height-104)*frame.aspect),height:CGFloat(height-104))
                ctx.saveGState(); ctx.translateBy(x:(CGFloat(width)-picture.width)/2,y:0)
                if let image=frame.image { UIImage(cgImage:image).draw(in:CGRect(origin:.zero,size:picture)) }
                let alpha:CGFloat=freeze ? 0.75 : CGFloat(max(0,1-abs(time-card.frame.t)/0.4))*0.75
                FeedbackDrawing.draw(frame:frame,corrected:alpha > 0 ? card.corrected : nil,size:picture,context:ctx,ghostAlpha:alpha,moveReference:card.frame.pose)
                ctx.restoreGState()
                // Mirror pixels and skeleton together; counter-mirror text so the caption stays readable.
                if card.frame.mirrored {
                    // Pixel mirroring is handled by the player's video surface, including the skeleton.
                    ctx.translateBy(x:CGFloat(width),y:0); ctx.scaleBy(x:-1,y:1)
                }
                UIColor.black.withAlphaComponent(0.8).setFill(); ctx.fill(CGRect(x:0,y:height-104,width:width,height:104))
                let paragraph=NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
                let attributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:UIColor.white,.paragraphStyle:paragraph]
                (card.cue+"\nYour swing (white) vs the fix (cyan)" as NSString).draw(in:CGRect(x:8,y:height-98,width:width-16,height:92),withAttributes:attributes)
                guard adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(i),timescale:15)) else { throw writer.error ?? APIError(message:"Replay frame write failed.") }
            }
        }
        input.markAsFinished(); let done=DispatchSemaphore(value:0); writer.finishWriting { done.signal() }
        guard done.wait(timeout:.now()+30) == .success,writer.status == .completed else { writer.cancelWriting(); throw writer.error ?? APIError(message:"Replay finalization failed.") }
    }
}
