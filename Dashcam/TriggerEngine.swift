// Rôle (P1-P2) : sources de déclenchement → ClipWriter.
// `.manual` (bouton SAUVER), `.captureButton` (MWDATInputs, `.capture`), `.impact` (MWDATMotion :
// ‖a‖ − g > seuil, debounce 10 s, seuil réglable, log des pics), `.phoneImpact` (CoreMotion, fallback).
// Seuil initial 3,0 g au-dessus de g — hypothèse à calibrer en P2. Cf. CLAUDE.md.
