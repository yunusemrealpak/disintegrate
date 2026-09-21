import AVFoundation
import AppKit
import Foundation

// usage: demo_frames <video> <outdir> <start> <duration> <fps> <width>
let a = CommandLine.arguments
let src = URL(fileURLWithPath: a[1])
let dir = URL(fileURLWithPath: a[2])
let start = Double(a[3])!, dur = Double(a[4])!, fps = Double(a[5])!, w = Int(a[6])!
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let asset = AVAsset(url: src)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 240)
gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 240)
gen.maximumSize = CGSize(width: w, height: 4000)

let n = Int(dur * fps)
for i in 0..<n {
    let t = CMTime(seconds: start + Double(i) / fps, preferredTimescale: 600)
    guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else { continue }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = String(format: "f%04d.png", i)
    try png.write(to: dir.appendingPathComponent(name))
}
print("wrote \(n) frames to \(dir.path)")
