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
    case .stream: String(localized: "Micro des lunettes")
    case .hfp: String(localized: "Micro des lunettes (mains libres, vidéo moins fluide)")
    case .off: String(localized: "Sans son")
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

/// Débit d'images demandé au SDK (valeurs acceptées : 2, 7, 15, 24, 30). 15 et 7 servent à tester si
/// la musique Bluetooth revient quand le flux vidéo laisse de la place (bug #256, 2026-09-27).
enum FrameRateSetting: UInt, CaseIterable, Identifiable, Sendable {
  case fps24 = 24, fps15 = 15, fps7 = 7
  var id: UInt { rawValue }
  var label: String { String(localized: "\(rawValue) images/s") }
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
  var frameRate: FrameRateSetting {
    didSet { UserDefaults.standard.set(Int(frameRate.rawValue), forKey: "frameRate") }
  }
  /// Choc détecté par l'iPhone → sauvegarde automatique (P2 anticipée, décision Julian 2026-09-27).
  var impactDetectionEnabled: Bool {
    didSet { UserDefaults.standard.set(impactDetectionEnabled, forKey: "impactDetection") }
  }
  var impactThreshold: ImpactThreshold {
    didSet { UserDefaults.standard.set(impactThreshold.rawValue, forKey: "impactThreshold") }
  }
  /// On attend ce délai après un choc avant de sauver : le clip contient aussi l'« après ».
  let impactPostRoll: TimeInterval = 10
  let bufferSeconds: TimeInterval = 45

  // MARK: - État exposé à l'UI

  private(set) var isActive = false
  private(set) var availableSeconds = 0
  private(set) var isSaving = false
  private(set) var justSaved = false
  private(set) var lastClip: SavedClip?
  private(set) var audioStatus = "—"
  /// Choc détecté, sauvegarde imminente (affiché par la mascotte).
  private(set) var impactPending = false
  private var awaitingStreamAudio = false
  /// Lunettes en pause (tap sur la branche), renseigné par WearablesModel.
  var isPausedByGlasses = false {
    didSet { if isPausedByGlasses != oldValue { updateLiveActivity() } }
  }
  var errorMessage: String?

  // MARK: - Pipeline (thread-safe, alimenté hors main actor)

  nonisolated let ring: RingBuffer
  nonisolated let impactDetector = PhoneImpactDetector()
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
    // Réglage de test (musique / #256) retiré de l'écran : toujours 24 fps.
    frameRate = .fps24
    impactDetectionEnabled = UserDefaults.standard.object(forKey: "impactDetection") as? Bool ?? true
    impactThreshold = ImpactThreshold(rawValue: UserDefaults.standard.double(forKey: "impactThreshold")) ?? .g12
    ring = RingBuffer(bufferSeconds: 45)
    Self.current = self
    // Live Activity refusée ou retirée en arrière-plan : on la recrée au retour au premier plan.
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.liveActivity.retryIfNeeded() }
    }
  }

  @ObservationIgnored private var foregroundObserver: NSObjectProtocol?

  // MARK: - Cycle de vie du stream (appelé par WearablesModel)

  /// `streamAudio` : l'audio du stream SDK est demandé (permission micro accordée).
  func streamDidStart(glassesName: String?, streamAudio: Bool) {
    guard !isActive else { return }
    isActive = true
    ring.clear()
    switch audioSource {
    case .stream:
      awaitingStreamAudio = streamAudio
      audioStatus = streamAudio
        ? String(localized: "démarrage…")
        : String(localized: "autorisation du micro manquante — vidéo seule")
    case .hfp:
      let ok = hfp.start(preferring: glassesName) { [weak self] buffer, hostTime in
        self?.ingestHFPAudio(buffer, hostTime: hostTime)
      }
      audioStatus = ok ? String(localized: "enregistré") : String(localized: "micro indisponible — vidéo seule")
    case .off:
      audioStatus = String(localized: "désactivé")
    }
    // Après le HFP (qui fixe la catégorie playAndRecord), sinon catégorie playback + mix.
    keepAlive.start()
    liveActivity.start(target: Int(bufferSeconds))
    if impactDetectionEnabled {
      impactDetector.start(threshold: impactThreshold.rawValue) { [weak self] g in
        Task { @MainActor in self?.impactDetected(g) }
      }
    }
    telemetry.start(audio: audioSource.rawValue, resolution: "\(resolution.rawValue) @ \(frameRate.rawValue) fps")
    log.notice("[P1] dashcam active — audio=\(self.audioStatus, privacy: .public) résolution=\(self.resolution.rawValue, privacy: .public)")
    uiTask = Task { [weak self] in
      while !Task.isCancelled {
        self?.refresh()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  /// `dashcamStillWanted` : coupure temporaire (reprise après un tap, perte Bluetooth) — on garde le
  /// keep-alive (sans lui iOS gèle l'app avant qu'elle puisse relancer la session, écran verrouillé)
  /// et la Live Activity (iOS refuse d'en recréer une en arrière-plan). Sinon, arrêt complet.
  func streamDidStop(dashcamStillWanted: Bool) {
    impactDetector.stop()
    if isActive {
      isActive = false
      uiTask?.cancel()
      uiTask = nil
      hfp.stop()
      ring.clear()
      availableSeconds = 0
      telemetry.stop()
      log.notice("[P1] stream arrêté — buffer vidé")
    }
    if dashcamStillWanted {
      isPausedByGlasses = true
      log.notice("[P1] reprise attendue — keep-alive et Live Activity conservés")
    } else {
      isPausedByGlasses = false
      keepAlive.stop()
      liveActivity.end()
      log.notice("[P1] dashcam arrêtée")
    }
  }

  private func refresh() {
    availableSeconds = Int(ring.availableSeconds(now: CACurrentMediaTime()).rounded(.down))
    if awaitingStreamAudio, telemetry.audioSamplesSeen > 0 {
      awaitingStreamAudio = false
      audioStatus = String(localized: "enregistré")
    }
    if calls.isOnCall { audioStatus = String(localized: "coupé pendant l'appel") }
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

  // MARK: - Choc (iPhone)

  private func impactDetected(_ g: Double) {
    guard isActive, !impactPending else { return }
    impactPending = true
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    log.notice("[P2] CHOC \(String(format: "%.1f", g), privacy: .public) g — sauvegarde dans \(Int(self.impactPostRoll), privacy: .public) s")
    Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .seconds(self.impactPostRoll))
      if self.isActive { await self.save(trigger: .phoneImpact) }
      self.impactPending = false
    }
  }

  // MARK: - Sauvegarde

  /// Renvoie `true` si un clip a été écrit.
  @discardableResult
  func save(trigger: TriggerSource) async -> Bool {
    guard !isSaving else { return false }
    let now = CACurrentMediaTime()
    guard let snapshot = ring.snapshot(seconds: bufferSeconds, now: now) else {
      errorMessage = String(localized: "Rien en mémoire à sauver pour l'instant.")
      return false
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
        snapshot, to: url, description: muted ? String(localized: "Dashhound — son coupé pendant un appel") : "Dashhound")
      let clip = await ClipStore.publish(url, duration: duration, date: date, audioMutedForCall: muted)
      lastClip = clip
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      let elapsed = CACurrentMediaTime() - started
      log.notice(
        "[P1] CLIP sauvé (\(trigger.rawValue, privacy: .public)) durée=\(String(format: "%.1f", duration), privacy: .public) s vidéo=\(snapshot.video.count, privacy: .public) audio=\(snapshot.audio.count, privacy: .public) écriture=\(String(format: "%.2f", elapsed), privacy: .public) s Photos=\(clip.savedToPhotos, privacy: .public) \(url.lastPathComponent, privacy: .public)"
      )
      if let photosError = clip.photosError {
        errorMessage = String(localized: "Clip gardé dans l'app, mais pas dans Photos : \(photosError)")
      }
      justSaved = true
      savedFlashTask?.cancel()
      savedFlashTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        self?.justSaved = false
      }
      return true
    } catch {
      errorMessage = error.localizedDescription
      log.error("[P1] échec du clip : \(error.localizedDescription, privacy: .public)")
      return false
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
  private var audioPeak: Float = 0
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
        let peakDB: Double = audioPeak > 0 ? 20 * log10(Double(audioPeak)) : -120
        line = String(
          format: "[P1] +%.0fs fps=%.1f keyframes=%ld maxGap=%.0fms audio=%.0f éch/s crête=%.0f dBFS | mémoire=%.0f s (%ld vidéo, %ld audio) | RAM=%.0f Mo",
          now - startedAt, Double(frames) / elapsed, keyframes, maxGap, Double(audioSamples) / elapsed,
          peakDB, ring.availableSeconds(now: now), counts.video, counts.audio, Self.footprintMB())
        windowStart = now
        frames = 0
        keyframes = 0
        maxGap = 0
        audioSamples = 0
        audioPeak = 0
      }
    }
    if let first { log.notice("\(first, privacy: .public)") }
    if let line { log.notice("\(line, privacy: .public)") }
  }

  /// Crête du signal (0…1) : dit si le micro capte encore quelque chose (Plans, appel…).
  private static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
    let n = Int(buffer.frameLength)
    if let data = buffer.floatChannelData?[0] {
      var m: Float = 0
      for i in 0..<n { m = max(m, abs(data[i])) }
      return m
    }
    if let data = buffer.int16ChannelData?[0] {
      var m: Int32 = 0
      for i in 0..<n { m = max(m, abs(Int32(data[i]))) }
      return Float(m) / Float(Int16.max)
    }
    return -1
  }

  func audio(_ buffer: AVAudioPCMBuffer, now: TimeInterval) {
    let level = Self.peak(buffer)
    let isFirst = lock.withLock { () -> Bool in
      audioPeak = max(audioPeak, level)
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
