# P1 — Verdict PROVISOIRE (2026-09-27)

**Statut : non validé.** Le cœur de la dashcam marche dans Dashhound et tient écran verrouillé, mais
les tests bloquants de `CLAUDE.md` ne sont pas tous passés : **trajet réel de 10 min, coupure
Bluetooth, appel reçu téléphone en poche, mesure batterie longue**. Ce document sera complété
après le trajet. Mesures ci-dessous : logs `[P1]` / `[P2]` de l'app et analyse des fichiers
(`scripts/probe_video.swift`, `scripts/audio_levels.swift`).

## Trajet réel du 2026-09-28 (journal iPhone `log collect`, 12 min filmées en 2 sessions)

| Point | Mesure |
|---|---|
| Clips | **26 clips**, tous 45–48 s une fois la mémoire pleine, 24 fps, **0 trou d'image** (écart max 82 ms) |
| Fluidité | 154 fenêtres de 5 s : médiane **24,0 fps**, minimum 18,3 ; **0 suspension iOS** |
| Double tap en roulant | **4/4** sauvegardes, sans coupure |
| Détection de choc à 3 g | ❌ **22 faux positifs en 12 min** (nids-de-poule, téléphone en poche) : 1 644 pics ≥ 1,2 g, 139 ≥ 3 g, 7 ≥ 8 g, **0 ≥ 10 g** (max 9,4 g) → seuil recalibré à **12 g** (choix 8/12/16/20 g), marqué bêta |
| Batterie | session 1 : 100 → 84 % en 7 min 06 s (**2,3 %/min**) ; session 2 : 76 → 49 % en 5,4 min (**~5 %/min**) ⇒ autonomie **~20 à ~43 min** selon les conditions — à mesurer sur une session longue |
| Musique / guidage vocal | inaudibles dans les lunettes pendant tout le trajet (limite Meta #256, confirmée) |
| Écran | **jamais verrouillé** pendant ce trajet (aucun événement de verrouillage) → le cas « poche, écran verrouillé » reste à valider sur trajet |
| Appel | l'appel de 19:10:40 a eu lieu **après** l'arrêt de la dashcam → non testé en roulant |

## Trajet du 2026-09-29 (journal iPhone, 17:02 → 17:19)

| Point | Mesure |
|---|---|
| **Poche, écran verrouillé** | ✅ 7 min 14 s verrouillé d'affilée, stream continu ; double tap → clip 45,9 s |
| **Coupure Bluetooth** (lunettes pliées) | ✅ « hinges closed » → reconnexion auto en 5,7 s, film reparti à 8 s |
| **Batterie** | 86 → 63 % en 8,2 min écran verrouillé = **2,8 %/min ⇒ ~35 min** depuis une charge pleine |
| **WhatsApp** | ❌ l'ouvrir / appeler met les lunettes en mode appel → caméra coupée par les lunettes ; le garde-fou arrêtait alors la dashcam → **corrigé** (relances patientes, reprise à la fin d'appel, mémoire gardée) |
| Détection de choc à 12 g | 2 déclenchements (12,7 et 13,7 g) → seuil **16 g** |
| Appel | WhatsApp : vidéo impossible pendant l'appel (limite Meta) ; appel téléphonique (27/09) : vidéo maintenue |

## Ce qui marche (mesuré)

| Point | Mesure |
|---|---|
| Clips rétroactifs | 45,5 à 48,0 s (5 clips « mémoire pleine »), départ sur keyframe, **0 trou d'image** (écart max 50 ms), dans Photos + Documents/Clips |
| Écriture d'un clip | 0,16 à 1,89 s |
| Fluidité | 24,0 fps médian ; GOP mesuré ≈ 3 s (16 keyframes / 46 s) |
| Écran verrouillé | stream maintenu (keep-alive) ; **1 seule suspension de 1,6 s en 7 min** (test A) |
| RAM | 25 à 59 Mo, stable |
| Son | micro des lunettes via l'audio du stream SDK (PCM 16 kHz mono) ; **synchro validée à l'oreille** par Julian |
| Appel | détecté (CallKit) ; **son du clip à −120 dBFS dès la seconde du début d'appel** — la conversation n'est jamais enregistrée. Écran verrouillé **pendant** l'appel (18:50) : iOS interrompt le keep-alive, 2 micro-gels de 1,5–1,6 s, ~17 fps, mais le stream tient (10 s mesurées) et les clips n'ont **aucun trou** (22,7 et 25,2 s) |
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

1. ~~Trajet réel~~ fait le 28/09 (clips 45–48 s, 0 trou, double tap 4/4) — **à refaire écran
   verrouillé, téléphone en poche**, et avec la détection de choc à 12 g : **0 faux positif sur
   20 min** exigé.
2. **Coupure Bluetooth** (lunettes pliées 10 s) → reconnexion auto, « Le buffer est vide ».
3. **Appel reçu téléphone en poche, prolongé** → la dashcam continue pendant **et au moins 1 min
   après** l'appel (relance du keep-alive à la fin de l'interruption : pas encore exercée, la
   dashcam avait été arrêtée 0,2 s après la fin de l'appel).
4. **Batterie** mesurée sur les 10 min réelles.
5. « Hey Meta, lance Dashhound » après configuration Developer Center.
