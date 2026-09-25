# P0 — Verdict (2026-09-25, soirée)

**Verdict : GO P1, sous conditions** (§ Recommandation). Le test bloquant « 2 min en hvc1, app en
arrière-plan, écran verrouillé, vidéo continue » **passe** — mais **seulement avec un keep-alive
audio** : sans lui, iOS suspend l'app en ~2 s et les lunettes coupent la session ~20 s plus tard.

## Environnement réel (≠ CLAUDE.md d'août)

| Élément | Mesuré ce soir |
|---|---|
| Xcode / Swift | **27.0** / **6.4** (licence à ré-accepter après la mise à jour) |
| iPhone | « julian's iPhone », iPhone17,1, **iOS 27.0**, UDID `[UDID]` |
| Lunettes | Ray-Ban Meta « RB Meta 0018 », BT Classic, protocole `com.meta.ar.wearable` |
| SDK DAT | 1.0.0 (SPM, version exacte) · XcodeGen 2.46.0 · plugin `mwdat-ios` installé |
| Signing | Personal Team `Y96VPLGJW7` OK — **refuse** les entitlements *Hotspot* et *Access Wi-Fi Information* (retirés du sample) ; `com.julian.*` indisponible → bundle ids `com.juliansalaun.*` |

Blocages rencontrés et levés : licence Xcode (sudo, Julian) · iPhone non visible (câble + confiance)
· `datAppOnTheGlassesUpdateRequired` → mise à jour de l'app DAT **sur les lunettes** via Meta AI.

## Mesures

### Latence de connexion (7 sessions)

| Étape | Min | Médiane | Max |
|---|---|---|---|
| `session.start()` → `.started` | 0,10 s | 0,50 s | 0,61 s |
| `stream.start()` → premier frame hvc1 | 1,64 s | **1,72 s** | 2,56 s |

→ **~2,2 s** de latence technique session + stream (hors délai humain entre les deux taps).

### Résolution / fps réels

- **360×640** (`.low`, config du sample) — `.medium` (504×896) **pas encore testé** (P1).
- **24,0 fps** moyens (fenêtres de 5 s : 22,3–26,2 au premier plan, **23,7–24,3** écran verrouillé
  avec keep-alive). Irrégularité d'arrivée Bluetooth : jusqu'à 330 ms entre deux frames, mais
  **écart de timestamps source ≤ 50 ms** → aucun frame perdu côté lunettes.
- GOP mesuré dans les fichiers : **1 keyframe / ~3 s** (63 keyframes sur 187 s).

### Comportement en background — 5 tests

| Test | Config | Résultat écran verrouillé |
|---|---|---|
| 1 | audio off, pas de keep-alive | frames stoppées ~2 s après le lock ; « Session ended by device » à +22 s ; clip 4,2 s |
| 2 | audio demandé mais HFP non routé | idem : trou de 15,5 s, RAM 55 → 27 Mo (gel), session coupée à +24 s ; clip 6,1 s |
| 3 | keep-alive silence, AirPods connectés | OK sur **25 s** seulement de lock (test trop court) ; clip 133,8 s sans trou |
| 4 | micro HFP lunettes actif, **keep-alive non relancé** (bug sonde) | micro-suspensions 1,7–3,7 s, **fps bridé à 15**, RAM pics **424 Mo**, session coupée à +63 s |
| **5** | **audio off + keep-alive silence** | ✅ **2 min 53 s verrouillé, 0 suspension (heartbeat 1 s), 24,0 fps, RAM 54–65 Mo** ; clip **187,1 s, 4490 frames, 0 trou > 50 ms** |

**Cause prouvée** (heartbeat + RAM) : iOS **suspend** l'app en background malgré les modes
`external-accessory` / `bluetooth-central` ; les lunettes, sans lecteur du flux, terminent la
session (même symptôme que l'issue GitHub #231). Jouer du silence (mode `audio`, catégorie
`.playback` + `.mixWithOthers`) empêche la suspension. La LED de capture reste allumée pendant
tout le stream — rien n'est dissimulé.

### Batterie lunettes

| Période | Relevés SDK | Pente |
|---|---|---|
| Test 5 (stream 24 fps, 3 min 24 s) | 70 % → 56 % | **4,1 %/min** |
| Tests 3 → 5 enchaînés (11,6 min dont ~7,2 min de stream) | 77 % → 56 % | ≤ 2,9 %/min de stream |

→ **Autonomie estimée : ~25–35 min de dashcam sur une charge pleine**, sous l'hypothèse de 30-45 min.
Relevés SDK granulaires/retardés : **mesure longue obligatoire en P1** (trajet 10 min). Thermique
lunettes : `none` sur toute la soirée (branches non mesurées au toucher).

### Audio

- Micro HFP des lunettes **routable** (`BluetoothHFP[RB Meta 0018]`), mais **pas quand des AirPods
  sont connectés** (ils deviennent la route par défaut).
- HFP actif ⇒ le SDK **descend la vidéo à 15 fps** (bande passante BT partagée) et ne suffit pas
  à empêcher les suspensions.
- Le sample crashe (`AVAudioEngine` : *inputNode != nullptr || outputNode != nullptr*) quand le
  micro HFP n'est pas routé → garde-fou ajouté.

### Keyframes — point P1 critique

Les `VideoFrame.sampleBuffer` reçus en direct **n'exposent pas** `kCMSampleAttachmentKey_NotSync`
(100 % des frames apparaissent « keyframe »), alors que les fichiers écrits en contiennent 1 / 3 s.
Le `RingBuffer` ne peut donc **pas** se fier à cet attachement : détecter les keyframes autrement
(type de NAL HEVC IDR/CRA dans les données) et le couvrir par un test unitaire.

### App `Dashcam` (squelette P0)

Build vert sur l'iPhone (Swift 6 strict) · enregistrement Meta AI ✅ · lunettes affichées
(batterie 55 %, thermique, port, lien) ✅ · session `started` en 0,14 s ✅ · permission caméra
accordée via le bouton + confirmation ✅.

## Critères de sortie P0

| Critère CLAUDE.md | État |
|---|---|
| Stream tient 2 min écran éteint | ✅ 2 min 53 s (test 5, avec keep-alive) |
| Vidéo lisible, continue | ✅ 187 s, 0 trou — ⚠️ pas encore **dans Photos** : fichier sur le Mac (`captures/p0/`, à AirDropper) ; l'enregistrement Photos automatique est un livrable P1 (`ClipStore`) |
| Latence / batterie / résolution-fps chiffrées | ✅ ci-dessus (batterie : estimation à confirmer) |

## Recommandation : GO P1, avec ces conditions intégrées dès le départ

1. **Keep-alive audio silencieux dans `Dashcam`** tant que la dashcam tourne — sans lui, rien ne
   marche téléphone en poche. Visible : Live Activity sur l'écran verrouillé (idée Julian).
2. **Audio HFP off par défaut** (proposition — CLAUDE.md dit « on ») : coûte 40 % de fps, route
   fragile (AirPods). Option activable ; à trancher par Julian.
3. **Détection de keyframes par parsing NAL** + tests unitaires `RingBuffer`.
4. **Pas de re-création de session en rafale** : ≥ 2 s entre deux `start()` (recommandation Meta,
   issue #231) — `WearablesModel` attend déjà 2 s avant la reconnexion auto.
5. **Mesures P1** : batterie sur 10 min réelles, `.medium` vs `.low` en background, RAM sur 10 min.

## Reproductibilité

`scripts/bootstrap.sh` puis `git -C vendor/dat apply ../../scripts/p0-cameraaccess.patch` (sample
patché : pas de coupure en background, entitlements Wi-Fi retirés, garde-fou audio, sonde
`com.julian.p0probe`, keep-alive, copie des vidéos dans `Documents/P0`). Analyse d'un clip :
`swift scripts/probe_video.swift <fichier>`. Logs bruts : `captures/` (gitignoré).
