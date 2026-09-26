// Pilote la Live Activity depuis l'app : démarrée avec le stream, mise à jour par paliers de 5 s
// et à chaque clip, terminée à l'arrêt de la dashcam.
import ActivityKit
import Foundation
import os

/// `Activity` n'est pas déclaré Sendable, mais ActivityKit le documente utilisable depuis n'importe
/// quel contexte : l'enveloppe permet de l'envoyer dans une Task sous Swift 6 strict.
private struct ActivityHandle: @unchecked Sendable {
  let activity: Activity<DashcamActivityAttributes>
}

@MainActor
final class LiveActivityController {
  private var activity: Activity<DashcamActivityAttributes>?
  private var lastState: DashcamActivityAttributes.ContentState?
  private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "LiveActivity")

  func start(target: Int) {
    // Nettoie une Live Activity laissée par une exécution précédente (crash, arrêt forcé).
    for stale in Activity<DashcamActivityAttributes>.activities where stale.id != activity?.id {
      let handle = ActivityHandle(activity: stale)
      Task { await handle.activity.end(nil, dismissalPolicy: .immediate) }
    }
    guard activity == nil else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      log.notice("Live Activities désactivées dans Réglages")
      return
    }
    let state = DashcamActivityAttributes.ContentState(secondsInMemory: 0, targetSeconds: target, lastClipAt: nil, isSaving: false)
    do {
      activity = try Activity.request(
        attributes: DashcamActivityAttributes(startedAt: Date()),
        content: ActivityContent(state: state, staleDate: nil))
      lastState = state
      log.notice("Live Activity démarrée")
    } catch {
      log.error("Live Activity refusée : \(error.localizedDescription, privacy: .public)")
    }
  }

  func update(secondsInMemory: Int, target: Int, lastClipAt: Date?, isSaving: Bool) {
    guard let activity else { return }
    let rounded = secondsInMemory >= target ? target : (secondsInMemory / 5) * 5
    let state = DashcamActivityAttributes.ContentState(
      secondsInMemory: rounded, targetSeconds: target, lastClipAt: lastClipAt, isSaving: isSaving)
    guard state != lastState else { return }
    lastState = state
    let handle = ActivityHandle(activity: activity)
    Task { await handle.activity.update(ActivityContent(state: state, staleDate: nil)) }
  }

  func end() {
    guard let activity else { return }
    self.activity = nil
    lastState = nil
    let handle = ActivityHandle(activity: activity)
    Task { await handle.activity.end(nil, dismissalPolicy: .immediate) }
  }
}
