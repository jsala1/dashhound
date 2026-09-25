# Design — Dashhound · Rewind

Mascotte : Dashhound, teckel à lunettes (noires, épaisses, sans logo) avec une LED bleue sur la branche droite — la LED est volontaire, elle raconte l'honnêteté du produit (capture visible). Générée par Julian via ChatGPT le 26/09/2026, découpée et nettoyée par le CTO Cowork.

| Fichier | Usage | Contraintes |
|---|---|---|
| `AppIcon-1024.png` | Icône iOS — à placer dans `Dashcam/Assets.xcassets/AppIcon.appiconset` (Xcode 26+ : une seule image 1024×1024 suffit) | 1024×1024, RGB sans transparence, coins pleins orange (#F87521) — iOS applique son propre masque |
| `Hero-Rewind-1080.png` | Visuel du post LinkedIn / écran d'accueil de l'app (P3) | 1080×1080, fond blanc cassé, le chien regarde en arrière = « Rewind » |
| `source/character-sheet.png` | Fiche personnage de référence — à joindre à tout nouveau prompt ChatGPT (« same character as attached ») | ne pas modifier |
| `source/icon-and-hero-composite.png` | Rendu brut dont sont extraits l'icône et le hero | — |

Palette : orange #F87521 · cuivre du pelage · noir des lunettes · blanc cassé #FCF8F4 (fond). Ne jamais écrire « Ray-Ban » ou « Meta » à côté du visuel.

## Poses (`poses/`)

14 poses découpées de la planche, carrées, fond blanc cassé `#FAF7F2` (pas de transparence) : `hero-run` · `run-1/2/3` · `face-curious` · `face-happy` · `face-wink` · `face-tired` · `face-alert` · `play-bow` · `sit-alert` · `walk` · `sniff` · `look-back`. Mapping état → pose et palette light/dark : `docs/UI_Dashhound.md`. Deux poses ont un bord de voisin à nettoyer (`hero-run` bas-droit, `sit-alert` haut-droit).
