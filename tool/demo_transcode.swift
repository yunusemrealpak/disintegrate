import AVFoundation
import CoreImage
import Foundation

// usage: demo_transcode <in> <out> <targetWidth> <bitrateKbps>
let a = CommandLine.arguments
guard a.count == 5,
      let targetW = Int(a[3]), let kbps = Int(a[4]) else {
    FileHandle.standardError.write("usage: demo_transcode <in> <out> <width> <kbps>\n".data(using: .utf8)!)
    exit(1)
}
let src = URL(fileURLWithPath: a[1])
let dst = URL(fileURLWithPath: a[2])
try? FileManager.default.removeItem(at: dst)

let asset = AVAsset(url: src)
let sem = DispatchSemaphore(value: 0)
var track: AVAssetTrack?
asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
    track = asset.tracks(withMediaType: .video).first
    sem.signal()
}
sem.wait()
guard let t = track else { print("no video track"); exit(1) }

let natural = t.naturalSize.applying(t.preferredTransform)
let srcW = abs(natural.width), srcH = abs(natural.height)
// Keep both dimensions even - H.264 requires it.
let outW = targetW - (targetW % 2)
let outH = Int((srcH / srcW * CGFloat(outW)).rounded()) & ~1

let reader = try AVAssetReader(asset: asset)
let readerOut = AVAssetReaderTrackOutput(track: t, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
reader.add(readerOut)

let writer = try AVAssetWriter(outputURL: dst, fileType: .mp4)
let writerIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: outW,
    AVVideoHeightKey: outH,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: kbps * 1000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: 60,
        AVVideoAllowFrameReorderingKey: true,
    ]
])
writerIn.expectsMediaDataInRealTime = false
writerIn.transform = t.preferredTransform
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerIn, sourcePixelBufferAttributes: nil)
writer.add(writerIn)
writer.shouldOptimizeForNetworkUse = true

writer.startWriting()
writer.startSession(atSourceTime: .zero)
reader.startReading()

// The writer input transform handles orientation, so render at the track's
// natural (pre-transform) size and let the container rotate it.
let renderW = Int(abs(t.naturalSize.width)), renderH = Int(abs(t.naturalSize.height))
let scaleW = (renderW == Int(srcW)) ? outW : outH
let scaleH = (renderW == Int(srcW)) ? outH : outW

let ctx = CIContext()
var pool: CVPixelBufferPool?
CVPixelBufferPoolCreate(nil, nil, [
    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey: scaleW,
    kCVPixelBufferHeightKey: scaleH,
    kCVPixelBufferIOSurfacePropertiesKey: [:],
] as CFDictionary, &pool)

let queue = DispatchQueue(label: "transcode")
let done = DispatchSemaphore(value: 0)
var frames = 0
writerIn.requestMediaDataWhenReady(on: queue) {
    while writerIn.isReadyForMoreMediaData {
        guard let sample = readerOut.copyNextSampleBuffer(),
              let img = CMSampleBufferGetImageBuffer(sample) else {
            writerIn.markAsFinished()
            writer.finishWriting { done.signal() }
            return
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &out)
        let ci = CIImage(cvPixelBuffer: img)
        let sx = CGFloat(scaleW) / ci.extent.width
        let sy = CGFloat(scaleH) / ci.extent.height
        ctx.render(ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy)), to: out!)
        adaptor.append(out!, withPresentationTime: time)
        frames += 1
    }
}
done.wait()
print("wrote \(dst.path)  \(outW)x\(outH)  \(frames) frames  status=\(writer.status.rawValue)")
