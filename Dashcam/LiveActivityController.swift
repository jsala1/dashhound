// Pilote la Live Activity depuis l'app : démarrée avec la dashcam, mise à jour par paliers de 5 s
// et à chaque clip, terminée seulement sur « Arrêter la dashcam ». iOS refuse d'en créer une quand
// l'app est en arrière-plan : on garde donc la même pendant les reprises (tap, coupure Bluetooth),
// et si iOS la retire quand même, on la recrée au prochain passage au premier plan.
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
  private var stateTask: Task<Void, Never>?
  /// La dashcam tourne mais la Live Activity n'a pas pu être (re)créée : à refaire au premier plan.
  private(set) var needsStart = false
  private var target = 45
  private var startedAt = Date()
  private let log = Logger(subsystem: "com.julian.glassesdashcam", category: "LiveActivity")

  func start(target: Int, startedAt: Date) {
    self.target = target
    self.startedAt = startedAt
    if let activity, activity.activityState == .active {
      needsStart = false
      return
    }
    // Nettoie une Live Activity laissée par une exécution précédente (crash, arrêt forcé).
    for stale in Activity<DashcamActivityAttributes>.activities {
      let handle = ActivityHandle(activity: stale)
      Task { await handle.activity.end(nil, dismissalPolicy: .immediate) }
    }
    activity = nil
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      log.notice("Live Activities désactivées dans Réglages")
      needsStart = false
      return
    }
    let state = lastState ?? DashcamActivityAttributes.ContentState(
      secondsInMemory: 0, targetSeconds: target, lastClipAt: nil, isSaving: false)
    do {
      let newActivity = try Activity.request(
        attributes: DashcamActivityAttributes(startedAt: startedAt),
        content: ActivityContent(state: state, staleDate: nil))
      activity = newActivity
      lastState = state
      needsStart = false
      observe(newActivity)
      log.notice("Live Activity démarrée")
    } catch {
      // Typiquement : app en arrière-plan (écran verrouillé). On réessaiera au premier plan.
      needsStart = true
      log.error("Live Activity refusée (\(error.localizedDescription, privacy: .public)) — nouvel essai au premier plan")
    }
  }

  /// À appeler quand l'app revient au premier plan.
  func retryIfNeeded() {
    guard needsStart else { return }
    start(target: target, startedAt: startedAt)
  }

  func update(secondsInMemory: Int, target: Int, lastClipAt: Date?, isSaving: Bool, isPaused: Bool) {
    let rounded = secondsInMemory >= target ? target : (secondsInMemory / 5) * 5
    let state = DashcamActivityAttributes.ContentState(
      secondsInMemory: rounded, targetSeconds: target, lastClipAt: lastClipAt, isSaving: isSaving, isPaused: isPaused)
    guard state != lastState else { return }
    lastState = state
    guard let activity else { return }
    let handle = ActivityHandle(activity: activity)
    Task { await handle.activity.update(ActivityContent(state: state, staleDate: nil)) }
  }

  /// Seulement sur « Arrêter la dashcam ».
  func end() {
    needsStart = false
    stateTask?.cancel()
    stateTask = nil
    lastState = nil
    guard let activity else { return }
    self.activity = nil
    let handle = ActivityHandle(activity: activity)
    Task { await handle.activity.end(nil, dismissalPolicy: .immediate) }
    log.notice("Live Activity terminée (arrêt de la dashcam)")
  }

  /// Journalise les changements d'état décidés par iOS ; si la Live Activity disparaît alors que
  /// la dashcam tourne, on la recrée au prochain premier plan.
  private func observe(_ activity: Activity<DashcamActivityAttributes>) {
    stateTask?.cancel()
    let handle = ActivityHandle(activity: activity)
    stateTask = Task { [weak self] in
      for await state in handle.activity.activityStateUpdates {
        self?.log.notice("Live Activity état=\(String(describing: state), privacy: .public)")
        if state == .dismissed || state == .ended {
          guard let self, self.activity?.id == handle.activity.id else { return }
          self.activity = nil
          self.needsStart = true
          return
        }
      }
    }
  }
}
