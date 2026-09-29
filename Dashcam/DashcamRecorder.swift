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

/// Durée du clip sauvé (réglage) ; un choc y ajoute ses 10 s d'après.
enum ClipLength: Int, CaseIterable, Identifiable, Sendable {
  case s30 = 30, s45 = 45, s60 = 60, s90 = 90, s120 = 120
  var id: Int { rawValue }
  var label: String { String(localized: "\(rawValue) s") }
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
  var clipLength: ClipLength {
    didSet {
      UserDefaults.standard.set(clipLength.rawValue, forKey: "clipLength")
      ring.bufferSeconds = bufferSeconds
    }
  }
  /// Secondes gardées en mémoire = durée du clip + l'« après » d'un choc.
  var bufferSeconds: TimeInterval { TimeInterval(clipLength.rawValue) + impactPostRoll }
  /// Début de la dashcam (chrono affiché), conservé pendant les coupures.
  private(set) var dashcamStartedAt: Date?

  // MARK: - État exposé à l'UI

  private(set) var isActive = false
  /// La dashcam est en marche (demandée par l'utilisateur), même pendant une coupure du stream
  /// (appel, lunettes pliées, tap) : la mémoire est gardée et la détection de choc reste active.
  private(set) var isDashcamOn = false
  /// Stream coupé mais dashcam en marche : on attend que les lunettes reviennent.
  var isInterrupted: Bool { isDashcamOn && !isActive }
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
  nonisolated private let timeline = MediaTimeline()

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
    impactThreshold = ImpactThreshold(rawValue: UserDefaults.standard.double(forKey: "impactThreshold")) ?? .g16
    let length = ClipLength(rawValue: UserDefaults.standard.integer(forKey: "clipLength")) ?? .s45
    clipLength = length
    ring = RingBuffer(bufferSeconds: TimeInterval(length.rawValue) + 10)
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
    if !isDashcamOn {  // vrai démarrage ; après une coupure on garde la mémoire et le chrono
      ring.clear()
      dashcamStartedAt = Date()
    }
    isDashcamOn = true
    timeline.startSegment()
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
    liveActivity.start(target: clipLength.rawValue, startedAt: dashcamStartedAt ?? Date())
    if impactDetectionEnabled, !impactDetector.isRunning {
      impactDetector.start(threshold: impactThreshold.rawValue) { [weak self] g in
        Task { @MainActor in self?.impactDetected(g) }
      }
    }
    telemetry.start(audio: audioSource.rawValue, resolution: "\(resolution.rawValue) @ \(frameRate.rawValue) fps")
    log.notice("[P1] dashcam active — audio=\(self.audioStatus, privacy: .public) résolution=\(self.resolution.rawValue, privacy: .public)")
    if uiTask == nil {
      uiTask = Task { [weak self] in
        while !Task.isCancelled {
          self?.refresh()
          try? await Task.sleep(for: .seconds(1))
        }
      }
    }
  }

  /// `dashcamStillWanted` : coupure temporaire (reprise après un tap, perte Bluetooth) — on garde le
  /// keep-alive (sans lui iOS gèle l'app avant qu'elle puisse relancer la session, écran verrouillé)
  /// et la Live Activity (iOS refuse d'en recréer une en arrière-plan). Sinon, arrêt complet.
  func streamDidStop(dashcamStillWanted: Bool) {
    if isActive {
      isActive = false
      hfp.stop()
      telemetry.stop()
      log.notice("[P1] stream arrêté — mémoire \(dashcamStillWanted ? "conservée" : "vidée", privacy: .public)")
    }
    if dashcamStillWanted, isDashcamOn {
      log.notice("[P1] reprise attendue — mémoire, détection de choc, keep-alive et Live Activity conservés")
      updateLiveActivity()
    } else {
      isDashcamOn = false
      dashcamStartedAt = nil
      isPausedByGlasses = false
      impactDetector.stop()
      uiTask?.cancel()
      uiTask = nil
      ring.clear()
      availableSeconds = 0
      keepAlive.stop()
      liveActivity.end()
      log.notice("[P1] dashcam arrêtée")
    }
  }

  /// Branché par WearablesModel : relance immédiate quand une autre app libère le micro des lunettes.
  func onGlassesAudioReleased(_ handler: @escaping @MainActor () -> Void) {
    keepAlive.onAudioReleased = handler
  }

  /// Réglage modifié (résolution…) : on repart d'une mémoire vide — pas de mélange de formats.
  func resetMemory() {
    ring.clear()
    availableSeconds = 0
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
      secondsInMemory: 0, target: clipLength.rawValue, lastClipAt: lastClip?.date, isSaving: isSaving,
      isPaused: isPausedByGlasses || isInterrupted)
  }

  // MARK: - Ingestion (hors main actor)

  nonisolated func ingestVideo(_ sample: CMSampleBuffer) {
    let now = CACurrentMediaTime()
    let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sample)
    guard sourcePTS.isNumeric else { return }
    let mapped = timeline.mapVideo(pts: sourcePTS.seconds, arrival: now)
    guard let retimed = sample.retimed(presentation: mapped) else { return }
    let isKeyframe = sample.isHEVCKeyframe()
    ring.appendVideo(retimed, isKeyframe: isKeyframe, hostTime: now)
    telemetry.video(sample, isKeyframe: isKeyframe, now: now, ring: ring)
  }

  /// Audio du stream SDK : son PTS est dans l'horloge des PTS vidéo (skill audio-streaming).
  nonisolated func ingestStreamAudio(_ frame: AudioFrame) {
    guard frame.pcmBuffer.frameLength > 0 else { return }  // 1re trame vide à chaque (re)démarrage
    let now = CACurrentMediaTime()
    guard let mapped = timeline.mapAudio(pts: frame.presentationTimeStamp.seconds) else { return }
    let pcm = calls.isOnCall ? frame.pcmBuffer.silenced() : frame.pcmBuffer
    let pts = CMTime(seconds: mapped, preferredTimescale: CMTimeScale(frame.pcmBuffer.format.sampleRate))
    guard let sample = pcm?.sampleBuffer(presentationTime: pts) else { return }
    ring.appendAudio(sample, hostTime: now)
    telemetry.audio(frame.pcmBuffer, now: now)
  }

  /// Micro HFP : daté directement sur l'heure de l'iPhone, l'horloge commune des clips.
  nonisolated private func ingestHFPAudio(_ buffer: AVAudioPCMBuffer, hostTime: TimeInterval) {
    let pcm = calls.isOnCall ? buffer.silenced() : buffer
    let pts = CMTime(seconds: hostTime, preferredTimescale: CMTimeScale(buffer.format.sampleRate))
    guard let sample = pcm?.sampleBuffer(presentationTime: pts) else { return }
    ring.appendAudio(sample, hostTime: hostTime)
    telemetry.audio(buffer, now: hostTime)
  }

  // MARK: - Choc (iPhone)

  private func impactDetected(_ g: Double) {
    guard isDashcamOn, !impactPending else { return }
    impactPending = true
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    log.notice("[P2] CHOC \(String(format: "%.1f", g), privacy: .public) g — sauvegarde dans \(Int(self.impactPostRoll), privacy: .public) s")
    Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .seconds(self.impactPostRoll))
      if self.isDashcamOn { await self.save(trigger: .phoneImpact, extraSeconds: self.impactPostRoll) }
      self.impactPending = false
    }
  }

  // MARK: - Sauvegarde

  /// Renvoie `true` si un clip a été écrit.
  @discardableResult
  func save(trigger: TriggerSource, extraSeconds: TimeInterval = 0) async -> Bool {
    guard !isSaving else { return false }
    let now = CACurrentMediaTime()
    // Pendant une coupure, « les 45 dernières secondes » sont celles d'avant la coupure.
    let reference = isActive ? now : (ring.lastVideoHostTime ?? now)
    let seconds = TimeInterval(clipLength.rawValue) + extraSeconds
    guard let snapshot = ring.snapshot(seconds: seconds, now: reference) else {
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

// MARK: - Horloge commune

/// Chaque session de stream a sa propre horloge (PTS des lunettes), qui repart à chaque session. On
/// recale chaque segment sur l'heure de l'iPhone au premier frame : la mémoire traverse les coupures
/// (appel, lunettes pliées, tap) avec une chronologie continue, et l'audio HFP (daté en heure iPhone)
/// s'aligne sans conversion.
private final class MediaTimeline: @unchecked Sendable {
  private let lock = NSLock()
  private var base: (pts: Double, host: Double)?

  func startSegment() { lock.withLock { base = nil } }

  func mapVideo(pts: Double, arrival: Double) -> Double {
    lock.withLock {
      if base == nil { base = (pts, arrival) }
      return base!.host + (pts - base!.pts)
    }
  }

  /// `nil` tant qu'aucune image du segment n'est arrivée (origine inconnue).
  func mapAudio(pts: Double) -> Double? {
    guard pts.isFinite else { return nil }
    return lock.withLock { base.map { $0.host + (pts - $0.pts) } }
  }
}

extension CMSampleBuffer {
  /// Copie datée sur l'horloge commune (le décalage DTS/PTS d'origine est conservé).
  fileprivate func retimed(presentation seconds: Double) -> CMSampleBuffer? {
    var timing = CMSampleTimingInfo()
    CMSampleBufferGetSampleTimingInfo(self, at: 0, timingInfoOut: &timing)
    let pts = CMTime(seconds: seconds, preferredTimescale: 90_000)
    let decode = timing.decodeTimeStamp
    timing.decodeTimeStamp = decode.isNumeric ? CMTimeAdd(pts, CMTimeSubtract(decode, timing.presentationTimeStamp)) : .invalid
    timing.presentationTimeStamp = pts
    var copy: CMSampleBuffer?
    guard CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault, sampleBuffer: self, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
      sampleBufferOut: &copy) == noErr
    else { return nil }
    return copy
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
