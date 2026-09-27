// Niveau sonore d'un clip seconde par seconde (crête en dBFS) : vérifie par ex. que le son est bien
// coupé pendant un appel. Usage : swift scripts/audio_levels.swift <clip.mov>
import AVFoundation

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let sem = DispatchSemaphore(value: 0)
Task {
  defer { sem.signal() }
  guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { print("pas d'audio"); return }
  let reader = try! AVAssetReader(asset: asset)
  let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1,
  ])
  reader.add(output)
  reader.startReading()
  var peaks: [Int: Float] = [:]
  while let sb = output.copyNextSampleBuffer() {
    let start = CMSampleBufferGetPresentationTimeStamp(sb).seconds
    let rate = CMSampleBufferGetFormatDescription(sb).flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 16000
    guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
    var length = 0
    var pointer: UnsafeMutablePointer<CChar>?
    CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
    guard let pointer else { continue }
    let samples = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: length / 4)
    for i in 0..<(length / 4) {
      let second = Int(start + Double(i) / rate)
      peaks[second] = max(peaks[second] ?? 0, abs(samples[i]))
    }
  }
  for second in peaks.keys.sorted() {
    let p = peaks[second]!
    let db = p > 0 ? 20 * log10(p) : -120
    print(String(format: "%3d s  %6.1f dBFS  %@", second, db, String(repeating: "█", count: max(0, Int((db + 60) / 2)))))
  }
}
sem.wait()
