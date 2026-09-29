// Mémoire glissante de la dashcam : les dernières `bufferSeconds + margin` secondes de vidéo hvc1
// (passthrough, jamais décodée) et d'audio, en RAM. `snapshot` renvoie de quoi écrire un clip qui
// démarre sur une keyframe et couvre au moins `seconds` (sauf si la mémoire est plus courte).
// Thread-safe : alimenté par les callbacks du SDK, lu par l'UI et le ClipWriter. Cf. CLAUDE.md.
import CoreMedia
import Foundation

/// Un échantillon en mémoire. `hostTime` = heure d'arrivée (s, horloge monotone), qui pilote la
/// fenêtre glissante ; les timestamps du média restent dans le `CMSampleBuffer`.
struct BufferedSample: @unchecked Sendable {
  let sample: CMSampleBuffer
  let hostTime: TimeInterval
  let isKeyframe: Bool
}

/// Contenu figé d'un clip : la vidéo commence sur une keyframe.
struct ClipSnapshot: @unchecked Sendable {
  let video: [BufferedSample]
  let audio: [BufferedSample]

  var duration: TimeInterval {
    guard let first = video.first, let last = video.last else { return 0 }
    return last.hostTime - first.hostTime
  }
}

final class RingBuffer: @unchecked Sendable {
  let bufferSeconds: TimeInterval
  /// Marge conservée au-delà de `bufferSeconds` pour toujours trouver une keyframe en amont (GOP ≈ 3 s).
  let margin: TimeInterval

  private let lock = NSLock()
  private var video: [BufferedSample] = []
  private var audio: [BufferedSample] = []

  init(bufferSeconds: TimeInterval = 45, margin: TimeInterval = 15) {
    self.bufferSeconds = bufferSeconds
    self.margin = margin
  }

  func appendVideo(_ sample: CMSampleBuffer, isKeyframe: Bool, hostTime: TimeInterval) {
    lock.withLock {
      video.append(BufferedSample(sample: sample, hostTime: hostTime, isKeyframe: isKeyframe))
      evict(now: hostTime)
    }
  }

  func appendAudio(_ sample: CMSampleBuffer, hostTime: TimeInterval) {
    lock.withLock {
      audio.append(BufferedSample(sample: sample, hostTime: hostTime, isKeyframe: true))
      evict(now: hostTime)
    }
  }

  /// Les `seconds` dernières secondes, en partant de la dernière keyframe arrivée au plus tard à
  /// `now − seconds` (clip ≥ `seconds`) ; si la mémoire est plus courte, de la première keyframe.
  /// `nil` s'il n'y a encore aucune keyframe.
  func snapshot(seconds: TimeInterval, now: TimeInterval) -> ClipSnapshot? {
    lock.withLock {
      let from = now - seconds
      guard
        let start = video.lastIndex(where: { $0.isKeyframe && $0.hostTime <= from })
          ?? video.firstIndex(where: \.isKeyframe)
      else { return nil }
      let clipVideo = Array(video[start...])
      let startHost = clipVideo[0].hostTime
      let clipAudio = audio.filter { $0.hostTime >= startHost }
      return ClipSnapshot(video: clipVideo, audio: clipAudio)
    }
  }

  /// Secondes réellement sauvables (depuis la première keyframe), plafonnées à `bufferSeconds`.
  func availableSeconds(now: TimeInterval) -> TimeInterval {
    lock.withLock {
      guard let firstKey = video.first(where: \.isKeyframe) else { return 0 }
      return min(max(now - firstKey.hostTime, 0), bufferSeconds)
    }
  }

  /// Vide la mémoire (perte des lunettes : le buffer est vide, on le dit).
  func clear() {
    lock.withLock {
      video.removeAll()
      audio.removeAll()
    }
  }

  /// Heure d'arrivée de la dernière image (pour sauver pendant une coupure du stream).
  var lastVideoHostTime: TimeInterval? {
    lock.withLock { video.last?.hostTime }
  }

  var counts: (video: Int, audio: Int) {
    lock.withLock { (video.count, audio.count) }
  }

  private func evict(now: TimeInterval) {
    let limit = now - (bufferSeconds + margin)
    if let keep = video.firstIndex(where: { $0.hostTime >= limit }) {
      if keep > 0 { video.removeFirst(keep) }
    } else {
      video.removeAll()
    }
    if let keep = audio.firstIndex(where: { $0.hostTime >= limit }) {
      if keep > 0 { audio.removeFirst(keep) }
    } else {
      audio.removeAll()
    }
  }
}
