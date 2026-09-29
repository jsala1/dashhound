// Audio de la dashcam : keep-alive (silence joué — sans lui iOS suspend l'app ~2 s après le
// verrouillage, cf. P0_VERDICT.md), micro HFP des lunettes, détection d'appel (son coupé pendant
// un appel, décision Julian 2026-09-26) et conversion PCM → CMSampleBuffer.
import AVFoundation
import CallKit
import CoreMedia
import os

private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "Audio")

// MARK: - Keep-alive

/// Joue du silence en continu (mode background `audio`) pour que iOS ne suspende pas l'app pendant
/// que la dashcam tourne. Aucun son audible, `.mixWithOthers` : ne coupe ni musique ni GPS. La LED
/// des lunettes reste allumée pendant tout le stream — rien n'est dissimulé.
@MainActor
final class AudioKeepAlive {
  private var engine: AVAudioEngine?
  private var observers: [NSObjectProtocol] = []
  /// La dashcam veut le keep-alive : à relancer après une interruption (appel), sinon iOS gèle l'app
  /// écran verrouillé une fois l'appel terminé (vu 2026-09-27 : rien ne le relançait).
  private var wanted = false
  /// Surveillance : relance le moteur s'il s'est arrêté (changement de route audio, WhatsApp, lunettes
  /// pliées…). Vu le 29/09 : après ces changements, la relance échouait (erreur 'what') et rien ne
  /// réessayait.
  private var watchdog: Task<Void, Never>?

  init() {
    // Diagnostic cohabitation (musique coupée pendant la dashcam) : interruptions et changements de
    // route audio, pour départager notre session du stream caméra (bug SDK #256).
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
        let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
        let reason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
        log.notice("[AUDIO] interruption \(type == .began ? "début" : "fin", privacy: .public) raison=\(reason.map(String.init) ?? "-", privacy: .public)")
        if type == .ended {
          Task { @MainActor [weak self] in self?.resumeAfterInterruption() }
        }
      })
    observers.append(
      center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
        log.error("[AUDIO] services média réinitialisés — relance du keep-alive")
        Task { @MainActor [weak self] in self?.resumeAfterInterruption() }
      })
    observers.append(
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portType.rawValue)[\($0.portName)]" }
        log.notice("[AUDIO] route raison=\(reason.map(String.init) ?? "-", privacy: .public) sorties=\(outputs.joined(separator: ", "), privacy: .public) autreAudio=\(AVAudioSession.sharedInstance().isOtherAudioPlaying, privacy: .public)")
      })
    observers.append(
      center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: nil) { note in
        let type = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
        log.notice("[AUDIO] autre app audio \(type == 1 ? "démarre" : "s'arrête", privacy: .public)")
      })
  }

  var isRunning: Bool { engine?.isRunning ?? false }

  private func resumeAfterInterruption() {
    guard wanted, !isRunning else { return }
    log.notice("keep-alive relancé après interruption")
    startEngine()
  }

  func start() {
    wanted = true
    if watchdog == nil {
      watchdog = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(3))
          guard let self else { return }
          if self.wanted, !self.isRunning {
            log.notice("keep-alive arrêté — relance (surveillance)")
            self.startEngine()
          }
        }
      }
    }
    startEngine()
  }

  private func startEngine() {
    if isRunning { return }
    engine?.stop()
    engine = nil
    let session = AVAudioSession.sharedInstance()
    do {
      if session.category != .playAndRecord {
        try session.setCategory(.playback, options: [.mixWithOthers])
      }
      try session.setActive(true)
    } catch {
      log.error("keep-alive : session audio \(error.localizedDescription, privacy: .public)")
    }
    let engine = AVAudioEngine()
    var format = engine.mainMixerNode.outputFormat(forBus: 0)
    if format.sampleRate == 0 || format.channelCount == 0 {
      format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    }
    // @Sendable : appelé sur le thread de rendu audio. Sans cette annotation, la closure hérite de
    // @MainActor et le contrôle d'isolation de Swift 6 fait un trap (SIGTRAP) au premier rendu.
    let source = AVAudioSourceNode(format: format) { @Sendable _, _, _, audioBufferList -> OSStatus in
      for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
        if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
      }
      return noErr
    }
    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    do {
      try engine.start()
      self.engine = engine
      log.notice("keep-alive démarré (catégorie \(session.category.rawValue, privacy: .public))")
    } catch {
      log.error("keep-alive : échec \(error.localizedDescription, privacy: .public)")
    }
  }

  func stop() {
    wanted = false
    watchdog?.cancel()
    watchdog = nil
    engine?.stop()
    engine = nil
  }
}

// MARK: - Micro HFP des lunettes

/// Capture le micro des lunettes par le profil Bluetooth « mains libres ». Mesuré en P0 : bride la
/// vidéo à ~15 fps et les AirPods volent la route s'ils sont connectés → on vise explicitement
/// l'entrée HFP des lunettes. Sans entrée HFP : pas de tap, pas de start (sinon AVAudioEngine lève
/// une exception fatale — crash du sample en P0).
@MainActor
final class HFPMicrophone {
  private var engine: AVAudioEngine?
  private(set) var inputName: String?

  /// `onBuffer` est appelé hors main actor avec un buffer copié et son heure hôte (s).
  func start(preferring glassesName: String?, onBuffer: @escaping @Sendable (AVAudioPCMBuffer, TimeInterval) -> Void) -> Bool {
    stop()
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .mixWithOthers])
      try session.setActive(true)
    } catch {
      log.error("HFP : session audio \(error.localizedDescription, privacy: .public)")
      return false
    }
    let hfpInputs = (session.availableInputs ?? []).filter { $0.portType == .bluetoothHFP }
    let glasses =
      hfpInputs.first { port in glassesName.map { port.portName.localizedCaseInsensitiveContains($0) } ?? false }
      ?? hfpInputs.first { !$0.portName.localizedCaseInsensitiveContains("AirPods") }
    guard let glasses else {
      log.error("HFP : aucune entrée des lunettes (entrées : \(hfpInputs.map(\.portName).joined(separator: ", "), privacy: .public))")
      return false
    }
    do {
      try session.setPreferredInput(glasses)
    } catch {
      log.error("HFP : setPreferredInput \(error.localizedDescription, privacy: .public)")
    }

    let engine = AVAudioEngine()
    let format = engine.inputNode.inputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      log.error("HFP : format d'entrée nul, enregistrement vidéo seule")
      return false
    }
    engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, time in
      guard let copy = buffer.copied() else { return }
      onBuffer(copy, AVAudioTime.seconds(forHostTime: time.hostTime))
    }
    do {
      try engine.start()
    } catch {
      engine.inputNode.removeTap(onBus: 0)
      log.error("HFP : démarrage \(error.localizedDescription, privacy: .public)")
      return false
    }
    self.engine = engine
    inputName = glasses.portName
    log.notice("HFP : micro \(glasses.portName, privacy: .public) à \(format.sampleRate, privacy: .public) Hz")
    return true
  }

  func stop() {
    guard let engine else { return }
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    self.engine = nil
    inputName = nil
  }
}

// MARK: - Appels

/// Suit les appels téléphoniques (CallKit) : pendant un appel, l'audio des clips est remplacé par
/// du silence. Garde les intervalles récents pour signaler un clip concerné.
final class CallMonitor: NSObject, CXCallObserverDelegate, @unchecked Sendable {
  private let observer = CXCallObserver()
  private let lock = NSLock()
  private var onCall = false
  private var endedHandler: (@Sendable () -> Void)?

  /// Appelé (hors main actor) à la fin d'un appel : les lunettes redeviennent disponibles.
  var onCallEnded: (@Sendable () -> Void)? {
    get { lock.withLock { endedHandler } }
    set { lock.withLock { endedHandler = newValue } }
  }
  private var callStart: TimeInterval?
  private var intervals: [ClosedRange<TimeInterval>] = []

  override init() {
    super.init()
    observer.setDelegate(self, queue: nil)
    onCall = observer.calls.contains { !$0.hasEnded }
    if onCall { callStart = CACurrentMediaTime() }
  }

  var isOnCall: Bool { lock.withLock { onCall } }

  /// Vrai si un appel a eu lieu (ou est en cours) entre `from` et `to` (heures hôte).
  func hadCall(from: TimeInterval, to: TimeInterval) -> Bool {
    lock.withLock {
      if let callStart, onCall, callStart <= to { return true }
      return intervals.contains { $0.lowerBound <= to && $0.upperBound >= from }
    }
  }

  func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    let active = callObserver.calls.contains { !$0.hasEnded }
    let now = CACurrentMediaTime()
    lock.withLock {
      if active, !onCall { callStart = now }
      if !active, onCall, let start = callStart {
        intervals.append(start...now)
        if intervals.count > 20 { intervals.removeFirst() }
        callStart = nil
      }
      onCall = active
    }
    log.notice("appel \(active ? "en cours — son coupé" : "terminé", privacy: .public)")
    if !active { onCallEnded?() }
  }
}

// MARK: - PCM

extension AVAudioPCMBuffer {
  func copied() -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
    copy.frameLength = frameLength
    let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
    let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for (src, dst) in zip(source, destination) {
      if let from = src.mData, let to = dst.mData { memcpy(to, from, Int(min(src.mDataByteSize, dst.mDataByteSize))) }
    }
    return copy
  }

  /// Même format et même durée, contenu nul (appel en cours).
  func silenced() -> AVAudioPCMBuffer? {
    guard let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
    silent.frameLength = frameLength
    for buffer in UnsafeMutableAudioBufferListPointer(silent.mutableAudioBufferList) {
      if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
    }
    return silent
  }

  /// CMSampleBuffer LPCM daté (`presentationTime` dans l'horloge des PTS vidéo du stream).
  func sampleBuffer(presentationTime: CMTime) -> CMSampleBuffer? {
    var formatDescription: CMAudioFormatDescription?
    guard
      CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: format.streamDescription, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription
      ) == noErr, let formatDescription
    else { return nil }
    let rate = CMTimeScale(format.sampleRate)
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: rate),
      presentationTimeStamp: CMTimeConvertScale(presentationTime, timescale: rate, method: .roundHalfAwayFromZero),
      decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard
      CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
        refcon: nil, formatDescription: formatDescription, sampleCount: CMItemCount(frameLength),
        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
        sampleBufferOut: &sample) == noErr, let sample,
      CMSampleBufferSetDataBufferFromAudioBufferList(
        sample, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0, bufferList: audioBufferList) == noErr
    else { return nil }
    return sample
  }
}
