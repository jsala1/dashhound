// Rôle (P1-P2) : sources de déclenchement → sauvegarde du clip (DashcamRecorder.save).
// P1 : `.manual` (bouton SAUVER). P2 : `.captureButton` (MWDATInputs, `.capture`), `.impact`
// (MWDATMotion, à venir), `.phoneImpact` (CoreMotion : ‖accélération utilisateur‖ > seuil, debounce
// 10 s, seuil réglable, log des pics). Seuil 12 g calibré sur le trajet réel du 2026-09-28 (téléphone
// en poche : 1 644 pics, max 9,4 g, 0 ≥ 10 g ; à 3 g → 22 faux positifs en 12 min).
import CoreMotion
import Foundation
import os

enum TriggerSource: String, Sendable {
  case manual = "bouton"
  case liveActivity = "Live Activity (écran verrouillé)"
  case captureButton = "bouton des lunettes"
  /// Tap sur la branche : les lunettes mettent la session en pause sans transmettre l'événement
  /// (mesuré 2026-09-26) — la pause elle-même sert de déclencheur ; reprise automatique ensuite.
  case glassesPause = "tap sur la branche (pause des lunettes)"
  /// Double tap sur le pavé tactile : remonté comme `.select(source: .captouch)` SANS pause du stream
  /// (mesuré 2026-09-27) — le déclencheur mains libres sans coupure.
  case glassesDoubleTap = "double tap sur la branche"
  case voice = "Hey Meta, lance Dashhound"
  case impact = "choc"
  case phoneImpact = "choc (téléphone)"
}

/// Seuils proposés dans les réglages (accélération hors gravité, en g). Un ancien réglage absent de
/// cette liste retombe sur le défaut, 16 g (trajet du 29/09 : 2 pics à 12,7 et 13,7 g en roulant).
enum ImpactThreshold: Double, CaseIterable, Identifiable, Sendable {
  case g12 = 12, g16 = 16, g20 = 20, g25 = 25
  var id: Double { rawValue }
  var label: String { String(localized: "\(Int(rawValue)) g") }
}

/// Détecte un choc avec l'accéléromètre de l'iPhone (l'app tourne en continu grâce au keep-alive).
/// Aucun geste sur les lunettes → aucune coupure du stream. Journalise les pics pour calibrer.
final class PhoneImpactDetector: @unchecked Sendable {
  /// Deux déclenchements sont séparés d'au moins 10 s (un choc secoue plusieurs fois).
  static let debounce: TimeInterval = 10
  /// Pics journalisés au-delà de ce niveau, pour calibrer le seuil sur de vrais trajets.
  static let logFloor = 1.2

  private let manager = CMMotionManager()
  private let queue: OperationQueue = {
    let q = OperationQueue()
    q.name = "com.julian.glassesdashcam.impact"
    q.maxConcurrentOperationCount = 1
    return q
  }()
  private let lock = NSLock()
  private var threshold = 3.0
  private var lastTrigger: TimeInterval = 0
  private var windowStart: TimeInterval = 0
  private var windowPeak = 0.0
  private var onImpact: (@Sendable (Double) -> Void)?
  private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "P2")

  func start(threshold: Double, onImpact: @escaping @Sendable (Double) -> Void) {
    guard manager.isDeviceMotionAvailable else {
      log.error("[P2] choc : accéléromètre indisponible")
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    lock.withLock {
      self.threshold = threshold
      self.onImpact = onImpact
      windowStart = now
      windowPeak = 0
    }
    manager.deviceMotionUpdateInterval = 1.0 / 50
    manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
      guard let self, let a = motion?.userAcceleration else { return }
      self.handle((a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
    }
    log.notice("[P2] détection de choc active, seuil \(threshold, privacy: .public) g")
  }

  var isRunning: Bool { manager.isDeviceMotionActive }

  func stop() {
    guard manager.isDeviceMotionActive else { return }
    manager.stopDeviceMotionUpdates()
    log.notice("[P2] détection de choc arrêtée")
  }

  private func handle(_ g: Double) {
    let now = ProcessInfo.processInfo.systemUptime
    let (fire, callback, windowLine) = lock.withLock { () -> (Bool, (@Sendable (Double) -> Void)?, String?) in
      windowPeak = max(windowPeak, g)
      var line: String?
      if now - windowStart >= 30 {
        line = String(format: "[P2] pic d'accélération sur 30 s : %.2f g (seuil %.0f g)", windowPeak, threshold)
        windowStart = now
        windowPeak = 0
      }
      guard g >= threshold, now - lastTrigger >= Self.debounce else { return (false, nil, line) }
      lastTrigger = now
      return (true, onImpact, line)
    }
    if let windowLine { log.notice("\(windowLine, privacy: .public)") }
    if g >= Self.logFloor {
      log.notice("[P2] pic \(String(format: "%.2f", g), privacy: .public) g\(fire ? " → CHOC" : "", privacy: .public)")
    }
    if fire { callback?(g) }
  }
}
