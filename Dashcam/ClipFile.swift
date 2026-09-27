// Écrit un ClipSnapshot dans un fichier .mov : la vidéo hvc1 est recopiée telle quelle (jamais
// ré-encodée), l'audio PCM est encodé en AAC. Les deux pistes partent de la même origine : le
// timestamp de présentation de la première image du clip (une image clé).
import AVFoundation
import CoreMedia

enum ClipWriter {
  enum Failure: Error, LocalizedError {
    case emptyClip
    case writer(String)

    var errorDescription: String? {
      switch self {
      case .emptyClip: String(localized: "Rien en mémoire à sauver.")
      case .writer(let message): String(localized: "Écriture du clip impossible : \(message)")
      }
    }
  }

  /// Écrit le clip et renvoie sa durée (s).
  static func write(_ snapshot: ClipSnapshot, to url: URL, description: String?) async throws -> TimeInterval {
    guard let firstVideo = snapshot.video.first,
      let videoFormat = CMSampleBufferGetFormatDescription(firstVideo.sample)
    else { throw Failure.emptyClip }

    let origin = CMSampleBufferGetPresentationTimeStamp(firstVideo.sample)
    let video = VideoTimeline(origin: origin).rebase(snapshot.video)
    guard let lastVideo = video.last else { throw Failure.emptyClip }
    let clipEnd = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(lastVideo), CMSampleBufferGetDuration(lastVideo))
    let audio = rebaseAudio(snapshot.audio, origin: origin, clipEnd: clipEnd)

    try? FileManager.default.removeItem(at: url)
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    } catch {
      throw Failure.writer(error.localizedDescription)
    }
    if let description {
      let item = AVMutableMetadataItem()
      item.identifier = .commonIdentifierDescription
      item.value = description as NSString
      writer.metadata = [item]
    }

    // Vidéo : passthrough (outputSettings nil), le format source sert d'indice.
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
    videoInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(videoInput) else { throw Failure.writer("video track") }
    writer.add(videoInput)

    // Audio : AAC à la fréquence et au nombre de canaux de la source.
    let audioPump: SamplePump? = {
      guard let first = audio.first,
        let format = CMSampleBufferGetFormatDescription(first),
        let source = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
      else { return nil }
      let audioInput = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC,
          AVSampleRateKey: source.mSampleRate,
          AVNumberOfChannelsKey: max(1, min(Int(source.mChannelsPerFrame), 2)),
        ])
      audioInput.expectsMediaDataInRealTime = false
      guard writer.canAdd(audioInput) else { return nil }
      writer.add(audioInput)
      return SamplePump(input: audioInput, samples: audio)
    }()

    guard writer.startWriting() else {
      throw Failure.writer(writer.error?.localizedDescription ?? "startWriting")
    }
    writer.startSession(atSourceTime: .zero)

    let videoPump = SamplePump(input: videoInput, samples: video)
    async let videoDone: Void = videoPump.run(queueLabel: "dashhound.clip.video")
    async let audioDone: Void = audioPump?.run(queueLabel: "dashhound.clip.audio") ?? ()
    _ = await (videoDone, audioDone)

    await writer.finishWriting()
    guard writer.status == .completed else {
      throw Failure.writer(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
    }
    return clipEnd.seconds
  }

  /// Audio recalé sur l'origine vidéo ; on ne garde que ce qui tombe dans la durée du clip, dans
  /// l'ordre strict des timestamps.
  private static func rebaseAudio(_ entries: [BufferedSample], origin: CMTime, clipEnd: CMTime) -> [CMSampleBuffer] {
    var result: [CMSampleBuffer] = []
    var previous = CMTime.negativeInfinity
    for entry in entries {
      let pts = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(entry.sample), origin)
      guard pts >= .zero, pts < clipEnd, pts > previous else { continue }
      var timing = CMSampleTimingInfo()
      CMSampleBufferGetSampleTimingInfo(entry.sample, at: 0, timingInfoOut: &timing)
      timing.presentationTimeStamp = pts
      timing.decodeTimeStamp = .invalid
      if let copy = entry.sample.retimed(&timing) {
        result.append(copy)
        previous = pts
      }
    }
    return result
  }
}

/// Recale les images sur une origine commune et garantit des timestamps de décodage strictement
/// croissants (le SDK peut livrer des durées nulles ou des timestamps qui se chevauchent), en
/// déclarant explicitement quelles images sont des images clés — sans cela Photos refuse le fichier.
private struct VideoTimeline {
  let origin: CMTime
  let fallbackDuration = CMTime(value: 1, timescale: 24)

  func rebase(_ entries: [BufferedSample]) -> [CMSampleBuffer] {
    var output: [CMSampleBuffer] = []
    output.reserveCapacity(entries.count)
    var nextDecode = CMTime.zero
    for (index, entry) in entries.enumerated() {
      let sample = entry.sample
      let duration = {
        let d = CMSampleBufferGetDuration(sample)
        return d.isValid && d > .zero ? d : fallbackDuration
      }()
      let sourceDecode = CMSampleBufferGetDecodeTimeStamp(sample)
      var decode = CMTimeSubtract(sourceDecode.isValid ? sourceDecode : CMSampleBufferGetPresentationTimeStamp(sample), origin)
      if index > 0, decode < nextDecode { decode = nextDecode }
      let presentation = CMTimeMaximum(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), origin), decode)

      var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: presentation, decodeTimeStamp: decode)
      guard let copy = sample.retimed(&timing) else { continue }
      copy.markSync(entry.isKeyframe)
      output.append(copy)
      nextDecode = CMTimeAdd(decode, duration)
    }
    return output
  }
}

extension CMSampleBuffer {
  fileprivate func retimed(_ timing: inout CMSampleTimingInfo) -> CMSampleBuffer? {
    var copy: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault, sampleBuffer: self, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
      sampleBufferOut: &copy)
    return status == noErr ? copy : nil
  }

  fileprivate func markSync(_ isSync: Bool) {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: true) as? [NSMutableDictionary],
      let first = attachments.first
    else { return }
    first[kCMSampleAttachmentKey_NotSync] = !isSync
    first[kCMSampleAttachmentKey_DependsOnOthers] = !isSync
  }
}

/// Alimente une piste du writer à son rythme, puis la termine.
private final class SamplePump: @unchecked Sendable {
  private let input: AVAssetWriterInput
  private let samples: [CMSampleBuffer]
  private var next = 0
  private var done = false

  init(input: AVAssetWriterInput, samples: [CMSampleBuffer]) {
    self.input = input
    self.samples = samples
  }

  func run(queueLabel: String) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      input.requestMediaDataWhenReady(on: DispatchQueue(label: queueLabel)) { [self] in
        guard !done else { return }
        while input.isReadyForMoreMediaData {
          guard next < samples.count, input.append(samples[next]) else {
            done = true
            input.markAsFinished()
            continuation.resume()
            return
          }
          next += 1
        }
      }
    }
  }
}
