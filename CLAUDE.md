# Dashhound Rewind

> **Nom (décision Julian, 2026-09-26)** : l'app s'appelle **Dashhound** (mascotte : un teckel à lunettes), sous-titre **Rewind** — « la dashcam qui regarde en arrière ». Ancien nom de travail : Glasses Dashcam. **Le bundle ID `com.juliansalaun.glassesdashcam`, le scheme `glassesdashcam://`, le dossier `Dashcam/` et la target Xcode ne changent PAS** (Developer Center, Config.xcconfig et signing en dépendent). Seuls changent : nom affiché, textes UI, docs, Developer Center. ⚠️ « Dash Hound » (2 mots) est déjà un jeu iOS sans rapport — on écrit toujours **Dashhound** en un mot.

App iOS native (Swift/SwiftUI) qui transforme des Ray-Ban Meta en **dashcam rétroactive** : les
lunettes streament en continu vers l'iPhone, l'app ne garde que les **45 dernières secondes** en
mémoire (ring buffer), et sur **déclencheur** (bouton de capture des lunettes, choc détecté par
l'IMU des lunettes, ou tap dans l'app) elle **fige ces 45 s en .mp4 dans Photos**.
Projet **perso** de Julian — hors gouvernance [employeur] (pas de Linear, pas de Notion équipe).
Pas fait pour aller à l'échelle : un test qui doit **marcher en vrai**, filmable pour un post
LinkedIn (cf. `docs/Showcase_LinkedIn.md`).

> **Source de vérité : ce fichier + `docs/PREREQUIS.md`.** Le projet frère
> `~/glasses-copilot` (même auteur, même Mac, même iPhone, mêmes lunettes) est une référence
> de méthode (CLAUDE.md, verdicts chiffrés) — pas une dépendance.

## Ce qui est établi (vérifié le 2026-09-25)

| Point | État | Source |
|---|---|---|
| SDK Meta Wearables Device Access Toolkit (DAT) iOS | **1.0.0, publié le 2026-09-24** | CHANGELOG du repo `facebook/meta-wearables-dat-ios` |
| Streaming vidéo en arrière-plan | ✅ avec `VideoCodec.hvc1` (HEVC compressé). `.raw` se met en pause en background | CHANGELOG 0.5.0, skill `camera-streaming` |
| Bouton de capture des lunettes exposé à l'app | ✅ **expérimental** — module `MWDATInputs`, événement `.capture(pressType, …)` | CHANGELOG 1.0.0, skill `inputs` |
| IMU des lunettes (accéléro, gyro, orientation) | ✅ **expérimental** — module `MWDATMotion`, 5-60 Hz, m/s² | CHANGELOG 1.0.0, skill `motion` |
| Audio des lunettes dans la vidéo | ✅ micro HFP (comme le sample `CameraAccess`) ; audio de stream expérimental en 1.0 | sample `VideoRecorder.swift` |
| Batterie / thermique des lunettes lisibles | ✅ `Device.batteryLevel`, `thermalLevel`, `StreamError.batteryLow / .thermalHot` | CHANGELOG 1.0.0 |
| Écriture des frames HEVC en fichier sans ré-encoder | ✅ `frame.sampleBuffer` → `AVAssetWriter` en passthrough | sample `CameraAccess/Media/VideoCaptureHandler.swift` |
| Publication App Store | ❌ bloquée (Developer Preview). Sans impact : usage perso, build TestFlight/Xcode | README DAT |
| App ID Meta obligatoire ? | ❌ en **Developer Mode**, `MetaAppID` vide/0 → pas d'attestation. ⚠️ Inputs et Motion « doivent être activés pour l'app dans le Developer Center » : à vérifier en P2 (cf. Risques) | skill `getting-started`, skills `inputs`/`motion` |
| LED de capture | Reste allumée en permanence pendant le stream — **assumé par Julian**. Interdit de la contourner (Acceptable Use Policy) | AUP Meta |

Machine (vérifiée le 2026-09-25, P0) : Xcode 27.0, Swift 6.4,
iPhone « julian's iPhone » iOS 27.0 (UDID `[UDID]`), lunettes **Ray-Ban Meta « RB Meta 0018 »** (sans écran),
Apple ID [email retiré], **Personal Team `Y96VPLGJW7`** (gratuit → re-signature tous
les 7 jours), pas de compte Meta developer / Developer Mode encore activé.

## Architecture cible

```
Ray-Ban Meta ──stream hvc1 (BT Classic / Wi-Fi)──▶ App iOS
     │ IMU (MWDATMotion, 30 Hz)                        │
     │ bouton capture (MWDATInputs)                    ▼
     │                                    RingBuffer (CMSampleBuffer HEVC, ~60 s, RAM)
     ▼                                                 │
 TriggerEngine ──(choc | bouton | tap)──▶ ClipWriter ─▶ .mp4 (passthrough, 45 s depuis 1re keyframe)
                                                       ▼
                                          Photos + notif + haptique + son
```

| Fichier | Rôle |
|---|---|
| `Dashcam/DashcamApp.swift` | `Wearables.configure()`, `.onOpenURL` → `handleUrl` (filtre `metaWearablesAction`) |
| `Dashcam/WearablesModel.swift` | Registration Meta AI, `DeviceSession` (AutoDeviceSelector), permission `.camera`, état device (batterie, thermique), reconnexion auto |
| `Dashcam/RingBuffer.swift` | Deque thread-safe de `(CMSampleBuffer, isKeyframe, hostTime)` ; éviction > `bufferSeconds + 15` ; `snapshot(seconds:now:)` renvoie les buffers depuis la **dernière keyframe ≤ now − seconds** (clip de 45 à 48 s, jamais tronqué ; décision 2026-09-26) · keyframes détectées par type de NAL (`HEVCKeyframe.swift`, copié du sample) · tests `DashcamTests` |
| `Dashcam/ClipWriter.swift` | `AVAssetWriter` passthrough hvc1 (adapté de `VideoCaptureHandler` du sample), timestamps re-basés à zéro, audio optionnel |
| `Dashcam/TriggerEngine.swift` | Sources : `.manual` (UI), `.captureButton` (Inputs), `.impact` (Motion : ‖a‖ − g > seuil, debounce 10 s, seuil réglable, log des pics), `.phoneImpact` (CoreMotion, fallback) |
| `Dashcam/ClipStore.swift` | Sauvegarde Photos (`PHPhotoLibrary`) + copie dans Documents ; `UNUserNotification` ; historique des clips |
| `Dashcam/Dashhound.swift` | `Palette` (9 tokens Color Sets clair/sombre), `DashhoundState` (état → pose, ligne, chiffre), `MascotCard` — cf. `docs/UI_Dashhound.md` |
| `Dashcam/DashcamRecorder.swift` | Ingestion frames/audio → RingBuffer, réglages (source audio stream/HFP/off, résolution), keep-alive, sauvegarde, télémétrie `[P1]` (fps, trous, suspensions, RAM) |
| `Dashcam/AudioSupport.swift` | Keep-alive silence, micro HFP (vise les lunettes, jamais d'`engine.start()` sans tap), `CallMonitor` (son coupé pendant un appel), PCM → CMSampleBuffer |
| `Dashcam/ContentView.swift` | Un seul écran : état stream, jauge « 45 s en mémoire », batterie/thermique lunettes, bouton **SAUVER** géant, dernier clip, réglages (durée, seuil, résolution) |

Décisions par défaut (modifiables dans l'app) : **45 s** (décision Julian 2026-09-25, était 60 s), `hvc1`, résolution `.medium` (504×896),
**24 fps**, audio **on — le son est indispensable** (Julian 2026-09-25 ; source à trancher en P1 : audio de stream SDK 1.0 vs HFP), Motion **30 Hz**, seuil d'impact **initial 3,0 g au-dessus de g**
(à calibrer en P2 — c'est une hypothèse, pas une mesure).

## Phasage — une phase = une milestone, tests bloquants

| Phase | Livrable | Tests bloquants avant la suivante |
|---|---|---|
| **P0 — Onboarding DAT** (1 soirée) | Developer Mode activé, sample `CameraAccess` buildé et lancé sur l'iPhone de Julian, stream visible depuis ses lunettes, **un enregistrement de 2 min en hvc1 avec l'app en arrière-plan** | Vidéo lisible dans Photos · stream tient 2 min écran éteint · `P0_VERDICT.md` avec : latence de connexion, batterie lunettes avant/après, résolution/fps réels obtenus |
| **P1 — Dashcam cœur** (1-2 soirées) | Ring buffer + déclencheur manuel (bouton app) + clip 45 s dans Photos + fonctionne téléphone en poche | Trajet réel de 10 min, 3 taps → 3 clips de 45 s ± 3 s (GOP mesuré ≈ 3 s), image continue (pas de trou, pas de frame verte), audio synchro · RAM stable (pas de fuite sur 10 min) · reconnexion propre après coupure BT |
| **P2 — Déclencheurs lunettes** (1-2 soirées) | Bouton de capture des lunettes (Inputs) + détection de choc (Motion) + fallback CoreMotion | 10 chocs simulés (tape sèche sur la branche / saut) → ≥ 9/10 clips · **0 faux positif sur un trajet de 20 min** (pavés, freinages) · bouton lunettes → clip en < 1 s |
| **P3 — Showcase** (1 soirée) | UI propre à filmer, clip vidéo + post LinkedIn (`docs/Showcase_LinkedIn.md`) | Julian valide le post avant publication |

## Règles de travail

1. **Ne jamais attaquer une phase tant que les tests de la précédente ne passent pas** — sur un
   cas réel, pas estimé. Le verdict est **écrit et chiffré** dans `P{n}_VERDICT.md`.
2. **Claude Code pilote Xcode.** CLI d'abord : `xcodegen generate` (projet depuis `project.yml`),
   `xcodebuild -scheme Dashcam -destination 'id=<UDID>'`, `xcrun devicectl list devices`,
   `xcrun devicectl device install app` / `device process launch --console`. L'interface Xcode
   (computer use) **seulement** pour ce que la CLI ne fait pas : premier choix du Team/signing,
   « faire confiance » au certificat sur l'iPhone, résolution de packages qui coince. Toute
   action GUI est annoncée avant d'être faite.
3. **Le sample officiel est la base, pas un modèle à réécrire.** `vendor/dat/samples/CameraAccess`
   (cloné par `scripts/bootstrap.sh`, gitignoré) : réutiliser `VideoCaptureHandler`,
   `AudioCaptureHandler`, `VideoFrameDecoder` en les copiant avec leur en-tête de licence.
   Lire d'abord les skills du plugin `mwdat-ios` (`getting-started`, `camera-streaming`,
   `inputs`, `motion`, `session-lifecycle`, `debugging`) — elles sont la doc à jour du SDK.
4. **Toute dépendance payante se demande avant** (compte Apple Developer payant 99 $/an,
   service tiers). Un `brew install` gratuit ne se demande pas.
5. **Clés/tokens jamais dans le repo.** `MetaAppID` / `ClientToken` (si un jour nécessaires)
   passent par `Config.xcconfig` gitignoré.
6. **Boucle courte, mesures réelles.** Chaque test terrain donne des chiffres (batterie, RAM,
   latence) dans le verdict de phase. Pas d'impression, pas de « ça devrait marcher ».
7. **Ne pas sur-ingénierer.** Pas de persistance de réglages compliquée, pas d'abstraction
   multi-plateforme, pas de tests unitaires au-delà de `RingBuffer` (celui-là, oui : keyframe,
   éviction, snapshot).
8. **AUP Meta respectée** : LED visible, aucune fonction de dissimulation, pas d'identification
   de personnes. Point non négociable même « pour le test ».

## Risques

- ⚠️ **Inputs / Motion « à activer dans le Developer Center »** — en Developer Mode sans
  App ID, il est possible que `addInputs` / `addMotion` remontent `permissionDenied`. Mitigation
  P2 : créer une app dans le Wearables Developer Center, activer les capacités, renseigner
  `MetaAppID`/`ClientToken`/`TeamID`. Fallback si toujours bloqué : CoreMotion du téléphone
  (seuil différent, téléphone en poche) + bouton app uniquement.
- ⚠️ **Modules expérimentaux** : API d'Inputs/Motion peut changer entre versions mineures. Pin
  la version `1.0.0` exacte dans `project.yml`.
- 🔋 **Batterie lunettes** — aucun chiffre public pour un stream continu hvc1. Hypothèse 30-45
  min. **Mesure P0 obligatoire** avant de promettre quoi que ce soit dans le post.
- 🔧 **Keyframes HEVC** — le clip doit démarrer sur une keyframe, sinon 1-2 s de bouillie verte.
  D'où le buffer de 60 s pour garantir 45 s propres. Vérifier `kCMSampleAttachmentKey_NotSync`.
- 🔧 **Reconnexion** — perte BT = buffer vidé. Reconnect auto + indicateur clair « buffer vide ».
- 🔧 **iOS et le background** — **mesuré en P0** : sans audio actif, iOS suspend l'app ~2 s après
  le verrouillage et les lunettes coupent la session ~20 s plus tard. Un keep-alive (silence joué,
  catégorie `.playback` + `.mixWithOthers`) tient 2 min 53 s sans suspension à 24 fps
  (`P0_VERDICT.md`). Le micro HFP seul ne suffit pas et bride la vidéo à 15 fps. Modes déclarés dans `project.yml` (`processing`, `bluetooth-central`,
  `external-accessory`, `audio`). Tester écran éteint, téléphone en poche, 10 min.
- 🎵 **Cohabitation audio** (question Julian 2026-09-26, non testé) — bug SDK ouvert #256 : le
  démarrage du stream caméra met la musique (A2DP) en pause sans reprise auto. Le micro HFP met les
  lunettes en mode appel (musique/GPS en qualité téléphone). Les appels passent en priorité et
  interrompent notre audio. **Intégré au test A/B P1** : Spotify en lecture + guidage Plans + appel
  entrant pendant les 2 min verrouillé ; noter ce qui coupe, reprend, et finit dans le clip.
- ⚖️ **Appels et enregistrement** — enregistrer une conversation sans consentement est un délit
  (art. 226-1 Code pénal). **Décision Julian 2026-09-26 : son du clip coupé pendant un appel**
  (vidéo seule, mention dans le clip) — détection via l'interruption audio / CallKit
  (`CXCallObserver`), implémentation en P1 avec l'audio.
- ⚖️ **Dashcam en France** — usage personnel toléré, la vidéo d'autrui n'est pas diffusable
  sans floutage. Le post LinkedIn n'utilisera qu'un clip **sans tiers identifiable**.
- 📷 **FOV** — le stream est plus étroit que les photos (retour dev GitHub #54). Acceptable.

## Idées retenues (hors phase en cours)

- **Indicateur sur l'écran verrouillé** (idée Julian 2026-09-25) : Live Activity (ActivityKit) sur
  l'écran verrouillé + Dynamic Island — « Dashcam active · 45 s en mémoire », bouton **Sauver**
  (Live Activity interactive via App Intent, iOS 17+). Sert aussi la transparence (AUP). Cible P1
  si simple, sinon P3. À vérifier : widget extension + App Group avec le Personal Team gratuit.

## Questions ouvertes

1. Seuil d'impact réel (g) sur des lunettes portées à vélo — à calibrer P2 avec les logs de pics.
2. Faut-il un App ID Meta pour Inputs/Motion en Developer Mode ? Réponse en P2.
3. Audio dans le clip (**on, non négociable**) : HFP (mesuré P0 : bride la vidéo à 15 fps, route volée par les AirPods) ou audio de stream expérimental 1.0 (exige une app Wearables Developer Center + permission `.microphone`) ? **Premier test de la P1** : A/B 2 min écran verrouillé avec keep-alive, mêmes mesures qu'en P0. Repli : micro iPhone.
