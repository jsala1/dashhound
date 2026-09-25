# Prérequis — checklist P0

Ce que Claude Code vérifie et fait, et ce que seul Julian peut faire (les lunettes sont sur
son nez, l'iPhone dans sa main).

## 1. Machine (Claude Code vérifie, `scripts/bootstrap.sh`)

| Élément | Exigé | Connu (août 2026, projet glasses-copilot) |
|---|---|---|
| Xcode | **26.4+** (skill getting-started, DAT 1.0) | 26.6 ✅ |
| Swift | 6.3+ | 6.3.3 ✅ |
| iPhone | iOS 17.2+ | « julian's iPhone », iOS 26.1 ✅ |
| XcodeGen | pour générer le projet | à installer (`brew install xcodegen`, gratuit) |
| Signing | Personal Team `Y96VPLGJW7` | ✅ déjà utilisé sur glasses-copilot — **re-signature tous les 7 jours** (contrainte du compte gratuit) |

## 2. Côté Meta (Julian, ~10 min, une seule fois)

1. **App Meta AI** à jour sur l'iPhone, lunettes appairées, **firmware à jour** (onglet Devices).
2. **Developer Mode** : Meta AI › *Settings* › *App Info* › taper **5 fois** sur le numéro de
   version › activer *Developer Mode* › confirmer. (Selon la version de l'app : *Settings › Your
   glasses › Developer Mode*.)
3. Compte sur le **Wearables Developer Center** (<https://wearables.developer.meta.com/>) :
   **pas nécessaire en P0/P1** (Developer Mode + `MetaAppID` vide = pas d'attestation).
   Deviendra nécessaire en **P2** si Inputs/Motion exigent une app enregistrée — on le saura au
   premier `permissionDenied`.
4. Au premier lancement de l'app : elle bascule vers Meta AI pour l'**enregistrement** puis la
   **permission caméra** (l'app prévient avant de basculer, comme le sample). Accepter, revenir.

## 3. Sur l'iPhone, au premier build

- *Réglages › Général › VPN et gestion de l'appareil* → faire confiance au certificat développeur.
- Autoriser Bluetooth, réseau local, micro, Photos, mouvement quand l'app le demande.
- **Mode Développeur iOS** activé (*Réglages › Confidentialité et sécurité › Mode développeur*),
  requis pour `devicectl` et les builds Xcode.

## 4. Boucle de build (Claude Code)

```bash
scripts/bootstrap.sh                                   # une fois
xcrun devicectl list devices                           # récupérer l'UDID de l'iPhone
xcodebuild -scheme Dashcam -destination "id=<UDID>" -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> <chemin .app dans DerivedData>
xcrun devicectl device process launch --device <UDID> --console com.juliansalaun.glassesdashcam
```

Logs de l'app : `Logger(subsystem: "com.julian.glassesdashcam", …)` + `--console` ci-dessus, ou
Console.app filtrée sur le sous-système. Le plugin `mwdat-ios` fournit aussi une skill
`live-debugging-mcp` pour inspecter une session DAT en direct.

## 5. Protocole de test P0 (Julian, avec les lunettes)

1. Lancer le sample `CameraAccess` (vendor/dat/samples) ou l'app en mode « P0 » : stream visible.
2. Démarrer un enregistrement, **éteindre l'écran**, téléphone en poche, marcher 2 min.
3. Revenir, stopper : la vidéo est-elle continue ? (pas de trou au passage en background)
4. Noter : batterie lunettes avant/après (l'app l'affiche), résolution/fps réellement obtenus,
   temps de connexion lunettes → premier frame, chaleur des branches.
5. Écrire `P0_VERDICT.md`. Go P1 seulement si la vidéo de 2 min est continue en background.
