// Partagé entre l'app et l'extension widget : la Live Activity « Dashhound regarde » (écran
// verrouillé + Dynamic Island) et le bouton Sauver utilisable sans déverrouiller. Rend aussi la
// capture visible sur le téléphone, comme la LED sur les lunettes (AUP).
import ActivityKit
import AppIntents
import Foundation

struct DashcamActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// Secondes sauvables, arrondies à 5 s (on ne pousse pas une mise à jour par seconde).
    var secondsInMemory: Int
    var targetSeconds: Int
    var lastClipAt: Date?
    var isSaving: Bool
    /// Lunettes en pause (tap sur la branche) : on ne filme plus jusqu'au tap suivant.
    var isPaused: Bool = false
  }

  var startedAt: Date
}

/// Bouton « Sauver » de la Live Activity : exécuté dans le processus de l'app (qui tourne, sinon
/// il n'y a pas de Live Activity).
struct SaveClipIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Sauver les 45 s"
  static let description = IntentDescription("Sauve les 45 dernières secondes de la dashcam dans Photos.")

  init() {}

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
      await DashcamRecorder.current?.save(trigger: .liveActivity)
    #endif
    return .result()
  }
}
