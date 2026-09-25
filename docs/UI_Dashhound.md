# UI Dashhound · Rewind — brief design pour Claude Code

**Date** : 2026-09-26 · **Décision Julian** : utiliser la mascotte et une palette light/dark pour rendre l'app friendly et *affordante*. **Quand** : après que le cœur P1 (ring buffer + clip dans Photos) fonctionne — les tokens et les états se posent tout de suite (c'est structurel), les illustrations se branchent ensuite. Ne pas retarder le test terrain P1 pour de la déco.

## Principe

Le chien **est** l'indicateur d'état. Sa posture dit ce que fait l'app ; le **chiffre** (secondes en mémoire, batterie) reste toujours écrit à côté — une posture ne remplace jamais une donnée. Utilisée à vélo/moto : un coup d'œil, une info, un bouton.

## Palette — tokens (Assets.xcassets → Color Sets avec apparence Any/Dark)

| Token | Light | Dark | Usage |
|---|---|---|---|
| `bg` | `#FCF8F4` | `#171412` | fond d'écran (blanc cassé chaud / noir chaud, même famille que l'icône sombre de la planche) |
| `surface` | `#FFFFFF` | `#23201C` | cartes, tuiles |
| `ink` | `#1E1A17` | `#F5EFE8` | texte principal |
| `inkMuted` | `#7A6F66` | `#A89C92` | texte secondaire, libellés |
| `hound` | `#F87521` | `#FF8A3D` | couleur primaire (orange de l'icône ; légèrement plus clair en dark pour le contraste sur noir) |
| `houndSoft` | `#FDE3D2` | `#3A2416` | fonds de jauge, badges, états passifs |
| `led` | `#4DA3FF` | `#6FB6FF` | la LED : point « en veille », halo « stream actif » — même sens que sur les lunettes |
| `ok` | `#2FA36B` | `#4CC585` | clip sauvé, lunettes connectées |
| `warn` | `#D9473A` | `#FF6B5E` | batterie < 15 %, thermique, déconnexion |

Contraste : vérifier `ink` sur `bg` et `#FFFFFF` sur `hound` (bouton) ≥ 4.5:1 dans les deux modes. Typo : SF Pro, Dynamic Type respecté ; le chiffre des secondes en `.largeTitle.monospacedDigit()`.

**Illustrations en dark mode** : les poses sont sur fond blanc cassé `#FAF7F2` (pas de transparence). Règle : la mascotte vit dans une **carte** (`MascotCard`) dont le fond reste `#FAF7F2` **dans les deux modes**, coins 24 pt — un « spot » clair sur fond sombre, assumé. Ne pas tenter de détourer les PNG (halos garantis). Si un jour on veut des poses détourées, on les regénère avec ChatGPT sur fond transparent, à partir de `design/source/character-sheet.png`.

## États → posture (fichiers dans `design/poses/`)

| État de l'app | Pose | Ligne du chien (1re personne, courte) | Détail |
|---|---|---|---|
| Premier lancement / enregistrement Meta AI | `hero-run` | « Salut, moi c'est Dashhound. » | hero plein cadre + bouton « Connecter mes lunettes » |
| Recherche des lunettes / session en cours de démarrage | `sniff` (alterner `run-1/2/3` en boucle 3 images, 400 ms) | « Je cherche tes lunettes… » | LED en `led` clignotant |
| **Veille active — buffer en cours de remplissage** | `sit-alert` | « Je regarde. » + **jauge 0→45 s** | jauge = arc orange `hound` sur `houndSoft` autour de la carte ou barre sous la carte ; le chiffre en gros |
| Buffer plein (45 s disponibles) | `face-alert` (ou `sit-alert` avec les « ! ») | « 45 s en mémoire. » | LED halo fixe |
| **Clip sauvé** (bouton, choc, bouton lunettes) | `look-back` | « Sauvé ! » | haptique `.success` + son court + toast `ok` avec miniature ; retour à `sit-alert` après 3 s |
| Pause / téléphone en poche sans stream | `play-bow` | « Je m'étire. » | — |
| Lunettes déconnectées / BT perdu | `face-curious` | « Hmm, je ne les vois plus. » + « Le buffer est vide. » | bandeau `warn` ; **dire que le buffer est vide**, c'est l'info critique |
| Batterie lunettes < 15 % ou thermique `hot` | `face-tired` | « J'ai chaud / Je fatigue — 12 %. » | bandeau `warn`, le pourcentage toujours affiché |
| Erreur permission / registration | `face-curious` | « Il me manque une autorisation. » + bouton vers Meta AI | — |
| Clip exporté / partagé | `face-happy` | « Bien joué. » | optionnel |
| `face-wink` | réservé à l'écran « À propos » / crédits | — | — |

## Écran unique (portrait, une main)

1. **Barre d'état** (haut) : pastille « Lunettes · connectées » (`ok`) · 🔋 % (`inkMuted`, `warn` < 15 %) · icône thermique si `thermalLevel` ≥ warm.
2. **MascotCard** (centre, ~45 % de la hauteur) : pose courante + ligne du chien + **le chiffre** des secondes en mémoire (`largeTitle`, `monospacedDigit`).
3. **Jauge** : arc ou barre, `hound` sur `houndSoft`, animée à chaque seconde ; à 45/45 elle se fige et pulse une fois.
4. **Bouton SAUVER** : pleine largeur, 72 pt de haut, fond `hound`, texte blanc `title2.bold` « Sauver les 45 s ». C'est le seul CTA. Haptique `.heavy` à l'appui. Zone tactile ≥ 44 pt partout ailleurs.
5. **Dernier clip** : miniature + durée + « Voir dans Photos » (`surface`).
6. **Engrenage** (haut droite) → réglages : durée (30/45/60 s), seuil de choc, audio on/off, résolution.

Pas de tab bar, pas d'onboarding multi-écrans, pas de compte. Mode clair/sombre : suivre le système (`@Environment(\.colorScheme)`), pas de toggle maison.

## Micro-interactions (3, pas plus)

- Passage `sit-alert` → `look-back` : crossfade 250 ms + léger scale 1.0→1.04→1.0 de la carte.
- Jauge : `withAnimation(.linear(duration: 1))` par seconde ; à 45 s un `spring` unique.
- LED : opacité 0.4↔1.0 en `repeatForever` pendant la recherche ; fixe en veille active ; éteinte si déconnecté.

## Implémentation (ordre)

1. Color Sets light/dark dans `Assets.xcassets` (9 tokens) + `enum DashhoundState` + `MascotCard` avec un mapping état → nom d'asset. Les 14 PNG de `design/poses/` vont dans un catalogue `Mascot` (1x suffit pour un test ; ce sont des images ≥ 230 px, on les affiche ≤ 180 pt).
2. Brancher la carte sur l'état réel de `WearablesModel` / du ring buffer. Vérifier les deux modes sur l'iPhone (Réglages › Apparence).
3. Micro-interactions, puis nettoyage des 2 poses avec un bord de voisin (`hero-run` bas-droit, `sit-alert` haut-droit) — recadrer ou regénérer.

Contraintes qui ne bougent pas : LED visible (elle est même dans l'UI), aucun texte « Ray-Ban » / « Meta » près de la mascotte, AUP respectée.
