// Tests du RingBuffer (seuls tests unitaires exigés par CLAUDE.md) : keyframe, éviction, snapshot.
// Flux simulé comme mesuré en P0 : 24 fps, une keyframe toutes les 72 images (3 s).
import CoreMedia
import Testing

private let fps = 24.0
private let gop = 72

/// CMSampleBuffer vidéo factice contenant une unité NAL HEVC du type demandé.
private func makeVideoSample(nalType: UInt8, pts: Double) -> CMSampleBuffer {
  var bytes: [UInt8] = [0, 0, 0, 2, nalType << 1, 0x01]
  var block: CMBlockBuffer?
  CMBlockBufferCreateWithMemoryBlock(
    allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count, blockAllocator: kCFAllocatorDefault,
    customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block)
  CMBlockBufferReplaceDataBytes(with: &bytes, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes.count)
  var format: CMFormatDescription?
  CMFormatDescriptionCreate(
    allocator: kCFAllocatorDefault, mediaType: kCMMediaType_Video, mediaSubType: kCMVideoCodecType_HEVC,
    extensions: nil, formatDescriptionOut: &format)
  var timing = CMSampleTimingInfo(
    duration: CMTime(value: 1, timescale: 24), presentationTimeStamp: CMTime(seconds: pts, preferredTimescale: 600),
    decodeTimeStamp: .invalid)
  var size = bytes.count
  var sample: CMSampleBuffer?
  CMSampleBufferCreateReady(
    allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
    sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
    sampleBufferOut: &sample)
  return sample!
}

/// Alimente le buffer avec `seconds` de flux à partir de `start` ; renvoie l'heure du dernier frame.
@discardableResult
private func feed(_ buffer: RingBuffer, seconds: Double, start: Double = 1000, firstFrameIndex: Int = 0) -> Double {
  var now = start
  for i in 0..<Int(seconds * fps) {
    let index = firstFrameIndex + i
    now = start + Double(i) / fps
    let isKey = index % gop == 0
    buffer.appendVideo(makeVideoSample(nalType: isKey ? 19 : 1, pts: now), isKeyframe: isKey, hostTime: now)
    if i % 24 == 0 {
      buffer.appendAudio(makeVideoSample(nalType: 1, pts: now), hostTime: now)
    }
  }
  return now
}

@Test func keyframeDetectionReadsTheNALType() {
  #expect(makeVideoSample(nalType: 19, pts: 0).isHEVCKeyframe())  // IDR_W_RADL
  #expect(makeVideoSample(nalType: 21, pts: 0).isHEVCKeyframe())  // CRA
  #expect(!makeVideoSample(nalType: 1, pts: 0).isHEVCKeyframe())  // TRAIL_R
}

@Test func snapshotCoversAtLeastTheRequestedSecondsAndStartsOnAKeyframe() throws {
  let buffer = RingBuffer(bufferSeconds: 45)
  let now = feed(buffer, seconds: 120)
  let clip = try #require(buffer.snapshot(seconds: 45, now: now))
  #expect(clip.video.first?.isKeyframe == true)
  #expect(clip.duration >= 45)
  #expect(clip.duration < 45 + 3)  // au plus un GOP de plus
}

@Test func evictionKeepsBufferPlusMargin() {
  let buffer = RingBuffer(bufferSeconds: 45, margin: 15)
  feed(buffer, seconds: 300)
  let counts = buffer.counts
  #expect(counts.video <= Int(60 * fps) + 1)
  #expect(counts.video >= Int(59 * fps))
  #expect(counts.audio <= 61)
}

@Test func shortBufferStartsOnFirstKeyframeAndSkipsLeadingFrames() throws {
  let buffer = RingBuffer(bufferSeconds: 45)
  // Le flux commence au milieu d'un GOP : les 10 premières images ne sont pas décodables.
  let now = feed(buffer, seconds: 20, firstFrameIndex: gop - 10)
  let clip = try #require(buffer.snapshot(seconds: 45, now: now))
  #expect(clip.video.first?.isKeyframe == true)
  #expect(clip.video.count == Int(20 * fps) - 10)
  #expect(abs(buffer.availableSeconds(now: now) - (20 - 10 / fps - 1 / fps)) < 0.1)
}

@Test func noKeyframeMeansNothingToSave() {
  let buffer = RingBuffer(bufferSeconds: 45)
  for i in 0..<10 {
    buffer.appendVideo(makeVideoSample(nalType: 1, pts: Double(i)), isKeyframe: false, hostTime: Double(i))
  }
  #expect(buffer.snapshot(seconds: 45, now: 10) == nil)
  #expect(buffer.availableSeconds(now: 10) == 0)
}

@Test func audioStartsWithTheClip() throws {
  let buffer = RingBuffer(bufferSeconds: 45)
  let now = feed(buffer, seconds: 120)
  let clip = try #require(buffer.snapshot(seconds: 45, now: now))
  let startHost = try #require(clip.video.first?.hostTime)
  #expect(!clip.audio.isEmpty)
  #expect(clip.audio.allSatisfy { $0.hostTime >= startHost })
}

@Test func availableSecondsIsCappedAndClearEmptiesTheBuffer() {
  let buffer = RingBuffer(bufferSeconds: 45)
  let now = feed(buffer, seconds: 120)
  #expect(buffer.availableSeconds(now: now) == 45)
  buffer.clear()
  #expect(buffer.counts.video == 0)
  #expect(buffer.availableSeconds(now: now) == 0)
  #expect(buffer.snapshot(seconds: 45, now: now) == nil)
}
