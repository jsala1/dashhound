// Rôle (P1-P2) : sources de déclenchement → sauvegarde du clip (DashcamRecorder.save).
// P1 : `.manual` (bouton SAUVER). P2 : `.captureButton` (MWDATInputs, `.capture`), `.impact`
// (MWDATMotion : ‖a‖ − g > seuil, debounce 10 s, seuil réglable, log des pics), `.phoneImpact`
// (CoreMotion, fallback). Seuil initial 3,0 g au-dessus de g — hypothèse à calibrer en P2.
enum TriggerSource: String, Sendable {
  case manual = "bouton"
  case liveActivity = "Live Activity (écran verrouillé)"
  case captureButton = "bouton des lunettes"
  /// Tap sur la branche : les lunettes mettent la session en pause sans transmettre l'événement
  /// (mesuré 2026-09-26) — la pause elle-même sert de déclencheur ; reprise automatique ensuite.
  case glassesPause = "tap sur la branche (pause des lunettes)"
  case voice = "Hey Meta, lance Dashhound"
  case impact = "choc"
  case phoneImpact = "choc (téléphone)"
}
