// Rôle (P1-P2) : sources de déclenchement → sauvegarde du clip (DashcamRecorder.save).
// P1 : `.manual` (bouton SAUVER). P2 : `.captureButton` (MWDATInputs, `.capture`), `.impact`
// (MWDATMotion : ‖a‖ − g > seuil, debounce 10 s, seuil réglable, log des pics), `.phoneImpact`
// (CoreMotion, fallback). Seuil initial 3,0 g au-dessus de g — hypothèse à calibrer en P2.
enum TriggerSource: String, Sendable {
  case manual = "bouton"
  case captureButton = "bouton des lunettes"
  case impact = "choc"
  case phoneImpact = "choc (téléphone)"
}
