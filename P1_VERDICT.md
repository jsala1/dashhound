# P1 — Verdict PROVISOIRE (2026-09-27)

**Statut : non validé.** Le cœur de la dashcam marche dans Dashhound et tient écran verrouillé, mais
les tests bloquants de `CLAUDE.md` ne sont pas tous passés : **trajet réel de 10 min, coupure
Bluetooth, appel reçu téléphone en poche, mesure batterie longue**. Ce document sera complété
après le trajet. Mesures ci-dessous : logs `[P1]` / `[P2]` de l'app et analyse des fichiers
(`scripts/probe_video.swift`, `scripts/audio_levels.swift`).

## Ce qui marche (mesuré)

| Point | Mesure |
|---|---|
| Clips rétroactifs | 45,5 à 48,0 s (5 clips « mémoire pleine »), départ sur keyframe, **0 trou d'image** (écart max 50 ms), dans Photos + Documents/Clips |
| Écriture d'un clip | 0,16 à 1,89 s |
| Fluidité | 24,0 fps médian ; GOP mesuré ≈ 3 s (16 keyframes / 46 s) |
| Écran verrouillé | stream maintenu (keep-alive) ; **1 seule suspension de 1,6 s en 7 min** (test A) |
| RAM | 25 à 59 Mo, stable |
| Son | micro des lunettes via l'audio du stream SDK (PCM 16 kHz mono) ; **synchro validée à l'oreille** par Julian |
| Appel | détecté (CallKit) ; **son du clip à −120 dBFS dès la seconde du début d'appel**, vidéo continue (clips 18:50:39/42 : 22,7 et 25,2 s, 0 trou) — la conversation n'est jamais enregistrée |
| Plans | le micro des lunettes continue de capter (−16 à −37 dBFS) |
| Live Activity | écran verrouillé + Dynamic Island, bouton Sauver sans déverrouiller ; conservée pendant les reprises |
| Tests unitaires | RingBuffer + détection keyframe : **7/7** |

## Déclencheurs

| Geste | Résultat mesuré |
|---|---|
| **Double tap sur la branche** | remonté comme `select(captouch)` **sans pause du stream** → sauvegarde **sans coupure** (geste recommandé) |
| Tap simple | les lunettes mettent la session en pause (aucun événement transmis) → sauvegarde à la pause, puis reprise auto : **~4,3 s de coupure** |
| Appui long bouton capture | `capture(.hold)` arrive stream actif → sauvegarde **avant** que les lunettes prennent la caméra ; puis garde-fou (3 reprises / 60 s) → arrêt propre en ~13 s avec message clair |
| Bouton Sauver (écran verrouillé) | OK |
| « Hey Meta, lance Dashhound » | code en place, **non testé** : capacité Voice Invocations pas encore configurée chez Meta |

## Ce qui coince

- **Musique et instructions GPS muettes dans les lunettes** tant que la caméra tourne : coupure
  ~2 s après le début du stream, identique à 15 et 7 fps et sans audio de stream (coupure 0,01 s
  après `.streaming`) ; même lecture routée vers un Sonos = OK ; aucune interruption côté app.
  → **limite Meta** (bug #256), remontée dans facebook/meta-wearables-dat-ios#312.
- **Tap simple = pause imposée** par les lunettes (4,3 s de trou) — contourné par le double tap.
- **Résolution** : en 504×896 + audio stream, le SDK redescend seul en 360×640 et ~15 fps 22 % du
  temps → défaut **360×640**.
- **Batterie** : ~1,9 %/min en stream (97 → 84 % en ~7 min) ⇒ **~50 min estimées** sur une charge.
  **Non confirmé** sur un trajet réel (P0 donnait 4,1 %/min avec le sample). La batterie est tombée
  à 20 % après la soirée de tests.

## Bugs trouvés et corrigés pendant la P1

Crash SIGTRAP (closures audio isolées au main actor) · app en mode compatibilité (UILaunchScreen) ·
Live Activity perdue et keep-alive coupé pendant les reprises · keep-alive non relancé après un
appel · alertes d'erreur en boucle masquant « Arrêter » (force-kill) · boucle de reprises quand les
lunettes filment elles-mêmes.

## Reste à faire pour valider la P1

1. **Trajet réel de 10 min**, écran verrouillé en poche : 3 sauvegardes (double tap, bouton écran
   verrouillé, tap simple), clips 45–48 s, 0 trou, pas d'image verte, son synchro.
2. **Coupure Bluetooth** (lunettes pliées 10 s) → reconnexion auto, « Le buffer est vide ».
3. **Appel reçu téléphone en poche** → la dashcam continue pendant et après l'appel.
4. **Batterie** mesurée sur les 10 min réelles.
5. « Hey Meta, lance Dashhound » après configuration Developer Center.
