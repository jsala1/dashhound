// Cœur de la dashcam : reçoit les frames hvc1 et l'audio (stream SDK ou micro HFP) dans le
// RingBuffer, garde l'app éveillée pendant le stream, sauve les 45 dernières secondes à la demande.
// Télémétrie `[P1]` (sous-système com.julian.glassesdashcam) pour chiffrer les tests terrain.
import AVFoundation
import MWDATCamera
import Observation
import QuartzCore
import UIKit
import os

enum AudioSource: String, CaseIterable, Identifiable, Sendable {
  case stream, hfp, off
  var id: String { rawValue }
  var label: String {
    switch self {
    case .stream: "Micro des lunettes (stream)"
    case .hfp: "Micro des lunettes (Bluetooth mains libres)"
    case .off: "Sans son"
    }
  }
}

enum VideoResolution: String, CaseIterable, Identifiable, Sendable {
  case low, medium
  var id: String { rawValue }
  var label: String {
    switch self {
    case .low: "360 × 640"
    case .medium: "504 × 896"
    }
  }
  var sdk: StreamingResolution {
    switch self {
    case .low: .low
    case .medium: .medium
    }
  }
}

@Observable
@MainActor
final class DashcamRecorder {
  // MARK: - Réglages (persistés, appliqués au prochain démarrage du stream)

  var audioSource: AudioSource {
    didSet { UserDefaults.standard.set(audioSource.rawValue, forKey: "audioSource") }
  }
  var resolution: VideoResolution {
    didSet { UserDefaults.standard.set(resolution.rawValue, forKey: "resolution") }
  }
  let bufferSeconds: TimeInterval = 45

  // MARK: - État exposé à l'UI

  private(set) var isActive = false
  private(set) var availableSeconds = 0
  private(set) var isSaving = false
  private(set) var justSaved = false
  private(set) var lastClip: SavedClip?
  private(set) var audioStatus = "—"
  /// Lunettes en pause (tap sur la branche), renseigné par WearablesModel.
  var isPausedByGlasses = false {
    didSet { if isPausedByGlasses != oldValue { updateLiveActivity() } }
  }
  var errorMessage: String?

  // MARK: - Pipeline (thread-safe, alimenté hors main actor)

  nonisolated let ring: RingBuffer
  nonisolated let calls = CallMonitor()
  nonisolated private let telemetry = Telemetry()
  nonisolated private let clock = VideoClock()

  /// Instance vivante, pour le bouton Sauver de la Live Activity (SaveClipIntent).
  static weak var current: DashcamRecorder?

  private let keepAlive = AudioKeepAlive()
  private let liveActivity = LiveActivityController()
  private let hfp = HFPMicrophone()
  private var uiTask: Task<Void, Never>?
  private var savedFlashTask: Task<Void, Never>?
  private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "P1")

  init() {
    audioSource = UserDefaults.standard.string(forKey: "audioSource").flatMap(AudioSource.init) ?? .stream
    // 360×640 par défaut : en 504×896 + audio du stream, le SDK redescend seul en 360×640 et à
    // ~15 fps 22 % du temps (test A, 2026-09-26) — et un changement de résolution en plein clip
    // risque de corrompre le passthrough.
    resolution = UserDefaults.standard.string(forKey: "resolution").flatMap(VideoResolution.init) ?? .low
    ring = RingBuffer(bufferSeconds: 45)
    Self.current = self
  }

  // MARK: - Cycle de vie du stream (appelé par WearablesModel)

  /// `streamAudio` : l'audio du stream SDK est demandé (permission micro accordée).
  func streamDidStart(glassesName: String?, streamAudio: Bool) {
    guard !isActive else { return }
    isActive = true
    ring.clear()
    switch audioSource {
    case .stream:
      audioStatus = streamAudio ? "stream (en attente des premières trames)" : "permission micro manquante — vidéo seule"
    case .hfp:
      let ok = hfp.start(preferring: glassesName) { [weak self] buffer, hostTime in
        self?.ingestHFPAudio(buffer, hostTime: hostTime)
      }
      audioStatus = ok ? "HFP : \(hfp.inputName ?? "?")" : "micro HFP indisponible — vidéo seule"
    case .off:
      audioStatus = "coupé (réglage)"
    }
    // Après le HFP (qui fixe la catégorie playAndRecord), sinon catégorie playback + mix.
    keepAlive.start()
    liveActivity.start(target: Int(bufferSeconds))
    telemetry.start(audio: audioSource.rawValue, resolution: resolution.rawValue)
    log.notice("[P1] dashcam active — audio=\(self.audioStatus, privacy: .public) résolution=\(self.resolution.rawValue, privacy: .public)")
    uiTask = Task { [weak self] in
      while !Task.isCancelled {
        self?.refresh()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  func streamDidStop() {
    guard isActive else { return }
    isActive = false
    uiTask?.cancel()
    uiTask = nil
    hfp.stop()
    keepAlive.stop()
    liveActivity.end()
    ring.clear()
    availableSeconds = 0
    telemetry.stop()
    log.notice("[P1] dashcam arrêtée — buffer vidé")
  }

  private func refresh() {
    availableSeconds = Int(ring.availableSeconds(now: CACurrentMediaTime()).rounded(.down))
    if audioSource == .stream, audioStatus.hasPrefix("stream (en attente"), telemetry.audioSamplesSeen > 0 {
      audioStatus = "stream : \(telemetry.audioFormatDescription)"
    }
    if calls.isOnCall { audioStatus = "coupé pendant l'appel" }
    updateLiveActivity()
  }

  private func updateLiveActivity() {
    liveActivity.update(
      secondsInMemory: availableSeconds, target: Int(bufferSeconds), lastClipAt: lastClip?.date, isSaving: isSaving,
      isPaused: isPausedByGlasses)
  }

  // MARK: - Ingestion (hors main actor)

  nonisolated func ingestVideo(_ sample: CMSampleBuffer) {
    let now = CACurrentMediaTime()
    let isKeyframe = sample.isHEVCKeyframe()
    clock.update(videoPTS: CMSampleBufferGetPresentationTimeStamp(sample).seconds, hostTime: now)
    ring.appendVideo(sample, isKeyframe: isKeyframe, hostTime: now)
    telemetry.video(sample, isKeyframe: isKeyframe, now: now, ring: ring)
  }

  /// Audio du stream SDK : son PTS est dans l'horloge des PTS vidéo (skill audio-streaming).
  nonisolated func ingestStreamAudio(_ frame: AudioFrame) {
    guard frame.pcmBuffer.frameLength > 0 else { return }  // 1re trame vide à chaque (re)démarrage
    let now = CACurrentMediaTime()
    let pcm = calls.isOnCall ? frame.pcmBuffer.silenced() : frame.pcmBuffer
    guard let sample = pcm?.sampleBuffer(presentationTime: frame.presentationTimeStamp) else { return }
    ring.appendAudio(sample, hostTime: now)
    telemetry.audio(frame.pcmBuffer, now: now)
  }

  /// Micro HFP : heure hôte ramenée dans l'horloge des PTS vidéo via le dernier frame reçu.
  nonisolated private func ingestHFPAudio(_ buffer: AVAudioPCMBuffer, hostTime: TimeInterval) {
    guard let offset = clock.offset else { return }
    let pcm = calls.isOnCall ? buffer.silenced() : buffer
    let pts = CMTime(seconds: hostTime + offset, preferredTimescale: CMTimeScale(buffer.format.sampleRate))
    guard let sample = pcm?.sampleBuffer(presentationTime: pts) else { return }
    ring.appendAudio(sample, hostTime: hostTime)
    telemetry.audio(buffer, now: hostTime)
  }

  // MARK: - Sauvegarde

  func save(trigger: TriggerSource) async {
    guard !isSaving else { return }
    let now = CACurrentMediaTime()
    guard let snapshot = ring.snapshot(seconds: bufferSeconds, now: now) else {
      errorMessage = "Rien en mémoire à sauver pour l'instant."
      return
    }
    isSaving = true
    updateLiveActivity()
    defer {
      isSaving = false
      updateLiveActivity()
    }
    let date = Date()
    let muted = calls.hadCall(from: snapshot.video.first?.hostTime ?? now, to: now)
    let url = ClipStore.newClipURL(date: date)
    let started = CACurrentMediaTime()
    do {
      let duration = try await ClipWriter.write(
        snapshot, to: url, description: muted ? "Dashhound — son coupé pendant un appel" : "Dashhound")
      let clip = await ClipStore.publish(url, duration: duration, date: date, audioMutedForCall: muted)
      lastClip = clip
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      let elapsed = CACurrentMediaTime() - started
      log.notice(
        "[P1] CLIP sauvé (\(trigger.rawValue, privacy: .public)) durée=\(String(format: "%.1f", duration), privacy: .public) s vidéo=\(snapshot.video.count, privacy: .public) audio=\(snapshot.audio.count, privacy: .public) écriture=\(String(format: "%.2f", elapsed), privacy: .public) s Photos=\(clip.savedToPhotos, privacy: .public) \(url.lastPathComponent, privacy: .public)"
      )
      if let photosError = clip.photosError { errorMessage = "Clip gardé dans l'app, mais pas dans Photos : \(photosError)" }
      justSaved = true
      savedFlashTask?.cancel()
      savedFlashTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        self?.justSaved = false
      }
    } catch {
      errorMessage = error.localizedDescription
      log.error("[P1] échec du clip : \(error.localizedDescription, privacy: .public)")
    }
  }
}

// MARK: - Horloge vidéo

/// Décalage « PTS vidéo − heure hôte » du dernier frame, pour dater l'audio HFP.
private final class VideoClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: TimeInterval?

  var offset: TimeInterval? { lock.withLock { value } }

  func update(videoPTS: TimeInterval, hostTime: TimeInterval) {
    guard videoPTS.isFinite else { return }
    lock.withLock { value = videoPTS - hostTime }
  }
}

// MARK: - Télémétrie

/// Même sonde qu'en P0 : fenêtres de 5 s (fps, keyframes, trous, audio, RAM, mémoire), heartbeat
/// 1 s pour détecter les suspensions iOS.
private final class Telemetry: @unchecked Sendable {
  private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "P1")
  private let lock = NSLock()
  private var windowStart: TimeInterval = 0
  private var frames = 0
  private var keyframes = 0
  private var maxGap = 0.0
  private var lastFrame: TimeInterval?
  private var firstFrameLogged = false
  private var startedAt: TimeInterval = 0
  private var audioSamples = 0
  private var audioSeen = 0
  private var audioFormat = ""
  private var heartbeat: DispatchSourceTimer?
  private var lastTick: TimeInterval = 0

  var audioSamplesSeen: Int { lock.withLock { audioSeen } }
  var audioFormatDescription: String { lock.withLock { audioFormat } }

  private var lifecycleObservers: [NSObjectProtocol] = []

  func start(audio: String, resolution: String) {
    let now = CACurrentMediaTime()
    if lifecycleObservers.isEmpty {
      let events: [(Notification.Name, String)] = [
        (UIApplication.didEnterBackgroundNotification, "APP background"),
        (UIApplication.willEnterForegroundNotification, "APP foreground"),
        (UIApplication.protectedDataWillBecomeUnavailableNotification, "ÉCRAN verrouillé"),
        (UIApplication.protectedDataDidBecomeAvailableNotification, "ÉCRAN déverrouillé"),
      ]
      lifecycleObservers = events.map { name, label in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [log] _ in
          log.notice("[P1] \(label, privacy: .public)")
        }
      }
    }
    lock.withLock {
      startedAt = now
      windowStart = now
      frames = 0
      keyframes = 0
      maxGap = 0
      lastFrame = nil
      firstFrameLogged = false
      audioSamples = 0
      audioSeen = 0
      lastTick = now
    }
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.julian.glassesdashcam.heartbeat"))
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { [weak self] in self?.tick() }
    timer.resume()
    lock.withLock { heartbeat = timer }
    log.notice("[P1] télémétrie : audio=\(audio, privacy: .public) résolution=\(resolution, privacy: .public)")
  }

  func stop() {
    lock.withLock {
      heartbeat?.cancel()
      heartbeat = nil
    }
  }

  private func tick() {
    let now = CACurrentMediaTime()
    let delta = lock.withLock { () -> TimeInterval in
      defer { lastTick = now }
      return now - lastTick
    }
    if delta > 1.5 {
      log.error("[P1] SUSPENSION : \(String(format: "%.1f", delta), privacy: .public) s sans heartbeat")
    }
  }

  func video(_ sample: CMSampleBuffer, isKeyframe: Bool, now: TimeInterval, ring: RingBuffer) {
    var line: String?
    var first: String?
    lock.withLock {
      if !firstFrameLogged {
        firstFrameLogged = true
        let dims = CMSampleBufferGetFormatDescription(sample).map(CMVideoFormatDescriptionGetDimensions)
        first = String(
          format: "[P1] PREMIER FRAME %.2f s après le démarrage, %dx%d", now - startedAt, dims?.width ?? 0, dims?.height ?? 0)
      }
      if let lastFrame { maxGap = max(maxGap, (now - lastFrame) * 1000) }
      lastFrame = now
      frames += 1
      if isKeyframe { keyframes += 1 }
      let elapsed = now - windowStart
      if elapsed >= 5 {
        let counts = ring.counts
        line = String(
          format: "[P1] +%.0fs fps=%.1f keyframes=%d maxGap=%.0fms audio=%.0f éch/s | mémoire=%.0f s (%d vidéo, %d audio) | RAM=%.0f Mo",
          now - startedAt, Double(frames) / elapsed, keyframes, maxGap, Double(audioSamples) / elapsed,
          ring.availableSeconds(now: now), counts.video, counts.audio, Self.footprintMB())
        windowStart = now
        frames = 0
        keyframes = 0
        maxGap = 0
        audioSamples = 0
      }
    }
    if let first { log.notice("\(first, privacy: .public)") }
    if let line { log.notice("\(line, privacy: .public)") }
  }

  func audio(_ buffer: AVAudioPCMBuffer, now: TimeInterval) {
    let isFirst = lock.withLock { () -> Bool in
      audioSamples += Int(buffer.frameLength)
      audioSeen += Int(buffer.frameLength)
      guard audioFormat.isEmpty else { return false }
      audioFormat = "\(Int(buffer.format.sampleRate)) Hz, \(buffer.format.channelCount) canal"
      return true
    }
    if isFirst {
      log.notice("[P1] PREMIÈRE TRAME AUDIO : \(self.audioFormatDescription, privacy: .public)")
    }
  }

  private static func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
  }
}
