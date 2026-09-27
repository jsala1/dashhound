// Rôle : registration Meta AI, DeviceSession (AutoDeviceSelector), permissions `.camera` et
// `.microphone`, stream caméra hvc1 (+ audio PCM si choisi) vers DashcamRecorder, état des lunettes
// (batterie, thermique, port, lien) et reconnexion auto. Cf. CLAUDE.md.
import MWDATCamera
import MWDATCore
import MWDATInputs
import Observation
import os

@Observable
@MainActor
final class WearablesModel {
  // MARK: - État exposé à l'UI

  private(set) var registrationState: RegistrationState
  private(set) var sessionState: DeviceSessionState = .idle
  private(set) var hasActiveDevice = false
  private(set) var deviceName: String?
  /// `nil` = inconnu. 0 est traité comme inconnu (canal pas encore prêt, cf. sample BirdSpotter).
  private(set) var batteryLevel: Int?
  private(set) var thermal = "—"
  /// Thermique `severe` ou pire : la mascotte passe en « J'ai chaud ».
  private(set) var isThermalHot = false
  private(set) var donState = "—"
  private(set) var linkState = "—"
  private(set) var cameraPermission = "—"
  private(set) var isCameraGranted = false
  private(set) var isMicrophoneGranted = false
  private(set) var streamState: StreamState = .stopped
  /// Bouton des lunettes (MWDATInputs, expérimental) — sonde P2 anticipée (décision Julian 2026-09-26).
  private(set) var inputsStatus = "—"
  /// « Hey Meta, lance Dashhound » (Voice Invocations, expérimental, à activer au Developer Center).
  private(set) var voiceStatus = "—"
  var errorMessage: String?

  let recorder: DashcamRecorder

  /// L'audio du stream est choisi mais la permission micro des lunettes manque.
  var needsMicrophonePermission: Bool {
    recorder.audioSource == .stream && sessionState == .started && isCameraGranted && !isMicrophoneGranted
  }
  /// L'utilisateur a demandé une session : on la relance si elle tombe (coupure BT, lunettes pliées).
  private(set) var wantsSession = false

  var isRegistered: Bool { registrationState == .registered }

  var registrationLabel: String {
    switch registrationState {
    case .registered: return String(localized: "enregistrée")
    case .registering: return String(localized: "en cours…")
    case .available: return String(localized: "non enregistrée")
    case .unavailable: return String(localized: "indisponible")
    @unknown default: return "?"
    }
  }

  // MARK: - Privé

  @ObservationIgnored private let wearables: WearablesInterface
  @ObservationIgnored private let selector: AutoDeviceSelector
  @ObservationIgnored private var session: DeviceSession?
  @ObservationIgnored private let sessionTokens = ListenerTokenBag()
  @ObservationIgnored private let deviceTokens = ListenerTokenBag()
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []
  @ObservationIgnored private var reconnectTask: Task<Void, Never>?
  @ObservationIgnored private var camera: MWDATCamera.Camera?
  @ObservationIgnored private let streamTokens = ListenerTokenBag()
  @ObservationIgnored private var restartStreamWhenStopped = false
  @ObservationIgnored private var inputs: Inputs?
  @ObservationIgnored private var inputsTask: Task<Void, Never>?
  @ObservationIgnored private let inputTokens = ListenerTokenBag()
  @ObservationIgnored private var autoResumeTask: Task<Void, Never>?
  @ObservationIgnored private var voice: VoiceInvocationsStream?
  @ObservationIgnored private let voiceTokens = ListenerTokenBag()
  @ObservationIgnored private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "Wearables")

  init(recorder: DashcamRecorder, wearables: WearablesInterface = Wearables.shared) {
    self.recorder = recorder
    self.wearables = wearables
    self.selector = AutoDeviceSelector(wearables: wearables)
    self.registrationState = wearables.registrationState

    tasks.append(
      Task { [weak self] in
        guard let stream = self?.wearables.registrationStateStream() else { return }
        for await state in stream {
          self?.registrationState = state
          self?.log.notice("registration=\(self?.registrationLabel ?? "?", privacy: .public)")
        }
      })
    tasks.append(
      Task { [weak self] in
        guard let stream = self?.selector.activeDeviceStream() else { return }
        for await deviceId in stream {
          self?.activeDeviceChanged(deviceId)
        }
      })
  }

  isolated deinit {
    tasks.forEach { $0.cancel() }
    reconnectTask?.cancel()
    session?.stop()
  }

  // MARK: - Registration

  func register() {
    guard registrationState != .registering else { return }
    Task {
      do {
        try await wearables.startRegistration()
      } catch let error as RegistrationError {
        errorMessage = error.description
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  // MARK: - Session

  func startSession() {
    wantsSession = true
    guard session == nil else { return }
    do throws(DeviceSessionError) {
      let newSession = try wearables.createSession(deviceSelector: selector)
      session = newSession
      // S'abonner avant start() pour ne rater aucune transition (skill session-lifecycle).
      newSession.statePublisher.listen { @Sendable [weak self] state in
        Task { @MainActor in self?.sessionStateChanged(state) }
      }.store(in: sessionTokens)
      newSession.errorPublisher.listen { @Sendable [weak self] error in
        Task { @MainActor in
          self?.log.error("session error: \(error.localizedDescription, privacy: .public)")
          self?.errorMessage = error.localizedDescription
        }
      }.store(in: sessionTokens)
      sessionState = .starting
      try newSession.start()
    } catch {
      errorMessage = error.localizedDescription
      sessionTokens.clear()
      session = nil
      sessionState = .idle
    }
  }

  func stopSession() {
    wantsSession = false
    autoResumeTask?.cancel()
    autoResumeTask = nil
    reconnectTask?.cancel()
    if let session {
      session.stop()  // → .stopped → clearStream() → arrêt complet (wantsSession = false)
    } else {
      // Arrêt pendant une reprise (pas de session ouverte) : couper keep-alive et Live Activity ici.
      recorder.streamDidStop(dashcamStillWanted: false)
    }
  }

  private func sessionStateChanged(_ state: DeviceSessionState) {
    sessionState = state
    log.notice("session=\(state.description, privacy: .public)")
    switch state {
    case .started:
      autoResumeTask?.cancel()
      autoResumeTask = nil
      Task {
        await refreshCameraPermission()
        await refreshMicrophonePermission()
        startStreamIfReady()
        attachInputs()
      }
    case .paused:
      // Le tap (ou l'appui) sur la branche met la session en pause sans nous donner l'événement :
      // la pause sert de déclencheur. La mémoire est intacte ; un second tap reprend le stream.
      scheduleAutoResume()
    case .stopped:
      detachInputs()
      // La session emporte la caméra (cascade parent → enfant) : le buffer est vide.
      clearStream()
      sessionTokens.clear()
      session = nil
      scheduleReconnectIfNeeded()
    default:
      break
    }
  }

  /// La dashcam ne s'arrête que sur « Arrêter la dashcam » (Julian, 2026-09-26). Une pause imposée
  /// par les lunettes (tap sur la branche) ne se relance pas depuis l'app : on sauve le clip, puis on
  /// ferme la session en pause ; la reconnexion auto en rouvre une neuve 2 s plus tard (plancher
  /// recommandé par Meta, issue #231). Ordre imposé : la fermeture vide la mémoire.
  private func scheduleAutoResume() {
    guard autoResumeTask == nil else { return }
    autoResumeTask = Task { [weak self] in
      guard let self else { return }
      if self.recorder.isActive {
        self.log.notice("[P2] pause des lunettes → sauvegarde")
        await self.recorder.save(trigger: .glassesPause)
      }
      self.autoResumeTask = nil
      guard !Task.isCancelled, self.wantsSession,
        self.sessionState == .paused || self.streamState == .paused
      else { return }
      self.log.notice("[P2] reprise auto : on ferme la session en pause pour en rouvrir une")
      self.session?.stop()
    }
  }

  /// Reconnexion auto : seulement si l'utilisateur voulait une session et qu'un device est actif.
  /// Pendant `.paused` on ne fait rien (skill session-lifecycle : attendre started/stopped).
  private func scheduleReconnectIfNeeded() {
    guard wantsSession, session == nil, hasActiveDevice else { return }
    reconnectTask?.cancel()
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled, let self, self.wantsSession, self.session == nil, self.hasActiveDevice
      else { return }
      self.log.notice("reconnexion auto")
      self.startSession()
    }
  }

  // MARK: - Stream caméra

  /// Attache la caméra dès que la session est prête et la caméra autorisée : la dashcam tourne
  /// tant que la session est ouverte. Audio du stream seulement si choisi et autorisé.
  func startStreamIfReady() {
    guard let session, sessionState == .started, isCameraGranted, camera == nil else { return }
    let streamAudio = recorder.audioSource == .stream && isMicrophoneGranted
    let config = StreamConfiguration(
      videoCodec: .hvc1,
      audioCodec: streamAudio ? .pcm(sampleRate: .rate16000, numberOfChannels: 1) : nil,
      resolution: recorder.resolution.sdk,
      frameRate: 24)
    do {
      guard let newCamera = try session.addCamera(config: config) else {
        errorMessage = String(localized: "Caméra des lunettes indisponible, réessaie.")
        return
      }
      camera = newCamera
      let stream = newCamera.stream
      let recorder = recorder
      let glassesName = deviceName
      // Callbacks du SDK sur ses propres threads : closures @Sendable, jamais isolées au main actor.
      stream.statePublisher.listen { @Sendable [weak self] state in
        Task { @MainActor in self?.streamStateChanged(state, glassesName: glassesName, streamAudio: streamAudio) }
      }.store(in: streamTokens)
      stream.errorPublisher.listen { @Sendable [weak self] error in
        Task { @MainActor in
          self?.log.error("stream error: \(error.localizedDescription, privacy: .public)")
          self?.errorMessage = error.localizedDescription
        }
      }.store(in: streamTokens)
      stream.videoFramePublisher.listen { @Sendable frame in
        recorder.ingestVideo(frame.sampleBuffer)
      }.store(in: streamTokens)
      if streamAudio {
        stream.audioFramePublisher.listen { @Sendable frame in
          recorder.ingestStreamAudio(frame)
        }.store(in: streamTokens)
      }
      streamState = .starting
      log.notice("stream start — \(self.recorder.resolution.rawValue, privacy: .public), audio stream=\(streamAudio, privacy: .public)")
      stream.start()
    } catch {
      camera = nil
      errorMessage = error.localizedDescription
    }
  }

  /// Relance le stream pour appliquer un réglage (audio, résolution) : le buffer repart de zéro.
  func restartStream() {
    guard let camera else {
      startStreamIfReady()
      return
    }
    restartStreamWhenStopped = true
    camera.stop()
  }

  private func streamStateChanged(_ state: StreamState, glassesName: String?, streamAudio: Bool) {
    streamState = state
    if state == .paused { recorder.isPausedByGlasses = true }
    if state == .streaming { recorder.isPausedByGlasses = false }
    log.notice("stream=\(String(describing: state), privacy: .public)")
    switch state {
    case .paused:
      // Le stream signale la pause ~1 s avant la session (mesuré) : on réagit au premier des deux.
      scheduleAutoResume()
    case .streaming:
      recorder.streamDidStart(glassesName: glassesName, streamAudio: streamAudio)
    case .stopped:
      clearStream()
      if restartStreamWhenStopped {
        restartStreamWhenStopped = false
        startStreamIfReady()
      }
    default:
      break
    }
  }

  private func clearStream() {
    streamTokens.clear()
    camera?.stop()
    camera = nil
    streamState = .stopped
    recorder.streamDidStop(dashcamStillWanted: wantsSession)
  }

  // MARK: - Bouton des lunettes (MWDATInputs)

  /// Sonde P2 anticipée : tous les événements sont loggés ; un appui court sur le bouton de capture
  /// sauve les 45 dernières secondes. Le tap du pavé tactile est seulement observé (bug connu : il
  /// peut mettre le stream en pause).
  private func attachInputs() {
    guard let session, sessionState == .started, inputs == nil else { return }
    do {
      guard let newInputs = try session.addInputs() else {
        inputsStatus = String(localized: "indisponible")
        return
      }
      inputs = newInputs
      newInputs.statePublisher.listen { @Sendable [weak self] state in
        Task { @MainActor in
          self?.inputsStatus = state == .active ? String(localized: "actif") : state.description
          self?.log.notice("[P2] inputs=\(state.description, privacy: .public)")
        }
      }.store(in: inputTokens)
      newInputs.errorPublisher.listen { @Sendable [weak self] error in
        Task { @MainActor in
          self?.inputsStatus = error == .permissionDenied ? String(localized: "refusé (Developer Center)") : error.description
          self?.log.error("[P2] inputs erreur : \(error.description, privacy: .public)")
        }
      }.store(in: inputTokens)
      let events = newInputs.events
      inputsTask = Task { [weak self] in
        for await event in events {
          self?.handleInput(event)
        }
      }
      log.notice("[P2] inputs attachés")
    } catch {
      inputsStatus = String(localized: "erreur : \(error.localizedDescription)")
      log.error("[P2] addInputs : \(error.localizedDescription, privacy: .public)")
    }
  }

  private func detachInputs() {
    inputsTask?.cancel()
    inputsTask = nil
    inputTokens.clear()
    inputs = nil
    inputsStatus = "—"
  }

  private func handleInput(_ event: InputEvent) {
    log.notice("[P2] ÉVÉNEMENT \(String(describing: event), privacy: .public) — stream=\(String(describing: self.streamState), privacy: .public)")
    if case .capture(.shortPress, _, _) = event {
      Task { await recorder.save(trigger: .captureButton) }
    }
  }

  // MARK: - Permissions

  func refreshCameraPermission() async {
    do {
      setCameraPermission(try await wearables.checkPermissionStatus(.camera))
    } catch {
      cameraPermission = String(localized: "erreur")
    }
  }

  /// Bascule vers Meta AI : n'appeler qu'après confirmation de l'utilisateur (comme le sample).
  func requestCameraPermission() async {
    do {
      setCameraPermission(try await wearables.requestPermission(.camera))
      await refreshMicrophonePermission()
      startStreamIfReady()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func refreshMicrophonePermission() async {
    isMicrophoneGranted = (try? await wearables.checkPermissionStatus(.microphone)) == .granted
  }

  /// Bascule vers Meta AI : n'appeler qu'après confirmation de l'utilisateur.
  func requestMicrophonePermission() async {
    do {
      isMicrophoneGranted = try await wearables.requestPermission(.microphone) == .granted
      if isMicrophoneGranted { restartStream() }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func setCameraPermission(_ status: PermissionStatus) {
    isCameraGranted = status == .granted
    cameraPermission = isCameraGranted ? String(localized: "accordée") : String(localized: "non accordée")
  }

  // MARK: - État des lunettes

  private func activeDeviceChanged(_ deviceId: DeviceIdentifier?) {
    hasActiveDevice = deviceId != nil
    deviceTokens.clear()
    guard let deviceId, let device = wearables.deviceForIdentifier(deviceId) else {
      voice?.stop()
      voiceStatus = "—"
      deviceName = nil
      batteryLevel = nil
      thermal = "—"
      isThermalHot = false
      donState = "—"
      linkState = "—"
      return
    }
    // L'état est relu sur le Device à chaque notification (livrée à l'abonnement puis à chaque changement).
    device.addDeviceStateListener { @Sendable [weak self] _ in
      Task { @MainActor in self?.read(device) }
    }.store(in: deviceTokens)
    device.addLinkStateListener { @Sendable [weak self] _ in
      Task { @MainActor in self?.read(device) }
    }.store(in: deviceTokens)
    read(device)
    startVoice(on: deviceId)
    scheduleReconnectIfNeeded()
  }

  // MARK: - « Hey Meta, lance Dashhound »

  /// Écoute les invocations vocales des lunettes (pas besoin de session ouverte).
  private func startVoice(on deviceId: DeviceIdentifier) {
    if voice == nil {
      do {
        let stream = try VoiceInvocationsStream(wearables: wearables)
        stream.invocationsPublisher.listen { @Sendable [weak self] invocation in
          guard let launch = invocation as? LaunchApp else { return }
          Task { @MainActor in await self?.handleVoice(launch) }
        }.store(in: voiceTokens)
        stream.errorPublisher.listen { @Sendable [weak self] error in
          Task { @MainActor in
            self?.voiceStatus = error.description
            self?.log.error("[P2] voix : \(error.description, privacy: .public)")
          }
        }.store(in: voiceTokens)
        voice = stream
      } catch {
        voiceStatus = error.localizedDescription
        return
      }
    }
    do {
      try voice?.start(deviceIdentifier: deviceId)
      voiceStatus = String(localized: "à l'écoute")
    } catch {
      voiceStatus = error.localizedDescription
      log.error("[P2] voix start : \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Dashcam active → sauve les 45 s ; arrêtée → la démarre. Toujours acquitter une seule fois.
  private func handleVoice(_ launch: LaunchApp) async {
    log.notice("[P2] « Hey Meta, lance Dashhound » — dashcam active=\(self.recorder.isActive, privacy: .public)")
    if recorder.isActive {
      let saved = await recorder.save(trigger: .voice)
      _ = saved
        ? await launch.responseHandle.sendSuccess(actionOutput: String(localized: "Clip sauvé"))
        : await launch.responseHandle.sendFailure(actionOutput: String(localized: "Rien à sauver"))
    } else {
      startSession()
      _ = await launch.responseHandle.sendSuccess(actionOutput: String(localized: "Dashcam démarrée"))
    }
  }

  private func read(_ device: Device) {
    deviceName = device.name.isEmpty ? String(localized: "Lunettes Meta") : device.name
    batteryLevel = device.batteryLevel.flatMap { $0 > 0 ? $0 : nil }
    thermal = String(describing: device.thermalLevel)
    switch device.thermalLevel {
    case .severe, .critical, .emergency, .shutdown: isThermalHot = true
    default: isThermalHot = false
    }
    donState = String(describing: device.donState)
    linkState = String(describing: device.linkState)
    log.notice(
      "device \(self.deviceName ?? "?", privacy: .public) batterie=\(self.batteryLevel.map(String.init) ?? "?", privacy: .public) thermique=\(self.thermal, privacy: .public) lien=\(self.linkState, privacy: .public)"
    )
  }
}
