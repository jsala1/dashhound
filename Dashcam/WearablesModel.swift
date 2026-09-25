// Rôle : registration Meta AI, DeviceSession (AutoDeviceSelector), permission `.camera`,
// état des lunettes (batterie, thermique, port, lien) et reconnexion auto. Cf. CLAUDE.md.
// P0 : pas encore de caméra attachée — la session est ouverte et observée, c'est tout.
import MWDATCore
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
  private(set) var donState = "—"
  private(set) var linkState = "—"
  private(set) var cameraPermission = "—"
  private(set) var isCameraGranted = false
  var errorMessage: String?
  /// L'utilisateur a demandé une session : on la relance si elle tombe (coupure BT, lunettes pliées).
  private(set) var wantsSession = false

  var isRegistered: Bool { registrationState == .registered }

  var registrationLabel: String {
    switch registrationState {
    case .registered: return "enregistrée"
    case .registering: return "en cours…"
    case .available: return "non enregistrée"
    case .unavailable: return "indisponible"
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
  @ObservationIgnored private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "Wearables")

  init(wearables: WearablesInterface = Wearables.shared) {
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
      newSession.statePublisher.listen { [weak self] state in
        Task { @MainActor in self?.sessionStateChanged(state) }
      }.store(in: sessionTokens)
      newSession.errorPublisher.listen { [weak self] error in
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
    reconnectTask?.cancel()
    session?.stop()
  }

  private func sessionStateChanged(_ state: DeviceSessionState) {
    sessionState = state
    log.notice("session=\(state.description, privacy: .public)")
    switch state {
    case .started:
      Task { await refreshCameraPermission() }
    case .stopped:
      sessionTokens.clear()
      session = nil
      scheduleReconnectIfNeeded()
    default:
      break
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

  // MARK: - Permission caméra

  func refreshCameraPermission() async {
    do {
      setCameraPermission(try await wearables.checkPermissionStatus(.camera))
    } catch {
      cameraPermission = "erreur"
    }
  }

  /// Bascule vers Meta AI : n'appeler qu'après confirmation de l'utilisateur (comme le sample).
  func requestCameraPermission() async {
    do {
      setCameraPermission(try await wearables.requestPermission(.camera))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func setCameraPermission(_ status: PermissionStatus) {
    isCameraGranted = status == .granted
    cameraPermission = isCameraGranted ? "accordée" : "non accordée"
  }

  // MARK: - État des lunettes

  private func activeDeviceChanged(_ deviceId: DeviceIdentifier?) {
    hasActiveDevice = deviceId != nil
    deviceTokens.clear()
    guard let deviceId, let device = wearables.deviceForIdentifier(deviceId) else {
      deviceName = nil
      batteryLevel = nil
      thermal = "—"
      donState = "—"
      linkState = "—"
      return
    }
    // L'état est relu sur le Device à chaque notification (livrée à l'abonnement puis à chaque changement).
    device.addDeviceStateListener { [weak self] _ in
      Task { @MainActor in self?.read(device) }
    }.store(in: deviceTokens)
    device.addLinkStateListener { [weak self] _ in
      Task { @MainActor in self?.read(device) }
    }.store(in: deviceTokens)
    read(device)
    scheduleReconnectIfNeeded()
  }

  private func read(_ device: Device) {
    deviceName = device.name.isEmpty ? "Lunettes Meta" : device.name
    batteryLevel = device.batteryLevel.flatMap { $0 > 0 ? $0 : nil }
    thermal = String(describing: device.thermalLevel)
    donState = String(describing: device.donState)
    linkState = String(describing: device.linkState)
    log.notice(
      "device \(self.deviceName ?? "?", privacy: .public) batterie=\(self.batteryLevel.map(String.init) ?? "?", privacy: .public) thermique=\(self.thermal, privacy: .public) lien=\(self.linkState, privacy: .public)"
    )
  }
}
