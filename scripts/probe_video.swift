// Analyse un clip : durée, frames, keyframes (sync samples), trous de PTS. Usage : swift scripts/probe_video.swift <fichier>
import AVFoundation
import CoreMedia

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
Task {
  defer { sem.signal() }
  do {
    let duration = try await asset.load(.duration).seconds
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { print("pas de piste vidéo"); return }
    let size = try await track.load(.naturalSize)
    let fds = try await track.load(.formatDescriptions)
    let codec = fds.first.map { CMFormatDescriptionGetMediaSubType($0) }.map { String(format: "%c%c%c%c", ($0 >> 24) & 255, ($0 >> 16) & 255, ($0 >> 8) & 255, $0 & 255) } ?? "?"
    let reader = try AVAssetReader(asset: asset)
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(out); reader.startReading()
    var frames = 0, keys = 0, last: Double?, maxGap = 0.0, gaps = 0
    var first: Double?
    while let sb = out.copyNextSampleBuffer() {
      guard CMSampleBufferGetNumSamples(sb) > 0 else { continue }
      frames += 1
      let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]]
      if (a?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) != true { keys += 1 }
      let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
      if first == nil { first = pts }
      if let l = last { let g = pts - l; maxGap = max(maxGap, g); if g > 0.15 { gaps += 1 } }
      last = pts
    }
    let span = (last ?? 0) - (first ?? 0)
    print(String(format: "durée=%.2f s  codec=%@  %dx%d  frames=%d  fps moyen=%.1f  keyframes=%d  trous>150ms=%d  trou max=%.0f ms",
                 duration, codec, Int(size.width), Int(size.height), frames, span > 0 ? Double(frames - 1) / span : 0, keys, gaps, maxGap * 1000))
    if let audio = try await asset.loadTracks(withMediaType: .audio).first {
      let range = try await audio.load(.timeRange)
      let afd = try await audio.load(.formatDescriptions).first
      let asbd = afd.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
      print(String(format: "audio : début=%.2f s  durée=%.2f s  %.0f Hz  %d canal", range.start.seconds, range.duration.seconds, asbd?.mSampleRate ?? 0, asbd?.mChannelsPerFrame ?? 0))
    } else {
      print("audio : aucune piste")
    }
  } catch { print("erreur: \(error)") }
}
sem.wait()
