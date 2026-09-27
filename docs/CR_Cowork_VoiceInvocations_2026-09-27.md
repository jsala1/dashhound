# CR Cowork — Voice Invocations sur le Wearables Developer Center (2026-09-27)

Réponse au brief `docs/Brief_Cowork_VoiceInvocations.md`. Rien ne change côté identifiants (Config.xcconfig intact).

## Voice Invocations — statut : **NON DISPONIBLE dans l'interface**
- Le Developer Center n'expose que deux permissions : **Camera access** et **Microphone access** (Configuration › Permissions). Aucune entrée « Voice Invocation », « app launch », « assistant » — ni dans Configuration, ni Product listing, ni Versions, ni Distribute, ni Required actions (vide).
- La doc Meta dit « Request the Voice Invocation permission and wait for approval », mais le bouton n'existe pas. **Bug/gating connu** : issue GitHub [#311](https://github.com/facebook/meta-wearables-dat-ios/issues/311) (SDK 1.0.0, même constat mot pour mot, sans réponse Meta à ce jour). Conséquence probable : « Hey Meta, start Dashhound » n'est pas reconnu tant que Meta n'ouvre pas la permission.
- Rien à remplir, donc pas de texte d'approbation soumis. À rejouer dès que l'entrée apparaît (surveiller #311 et le CHANGELOG DAT).

## Nom prononcé — fait
- Le keyword vocal = le champ **« App name »** du **Product listing** (« the name you provide acts as the keyword the voice service matches » — doc Voice Invocations). Il était encore « Glasses Dashcam » → passé à **« Dashhound »**. Une seule langue possible (pas de champ par langue) ; c'est le même mot en FR et EN.
- Version **1.1.0** (Minor) créée pour figer ce nom : build « In Progress » au moment du CR (1.0.0 est passée « Ready »). Aucune version n'est assignée au canal Beta, aucun testeur invité — inutile en Developer Mode.
- Icônes du Product listing (light/dark, 1024×1024) : **non uploadées** — l'extension Chrome ne peut pas pousser un fichier local. À faire à la main par Julian si utile : `design/AppIcon-1024.png` sur les deux emplacements (2 clics). Ne conditionne pas la voix.

## Statuts des capacités
| Capacité | Statut Developer Center |
|---|---|
| Camera | **Actif**, rationale enregistrée, pas de revue |
| Microphone (« Audio Streaming ») | **Actif**, rationale enregistrée, pas de revue |
| Inputs | **Aucune entrée dans l'interface** (idem CR du 26/09) |
| Motion | **Aucune entrée dans l'interface** (idem) |
| Voice Invocations | **Aucune entrée dans l'interface** (cf. #311) |

## Avertissements affichés
- Product listing : « Everything on this page is public » (le nom Dashhound et les icônes seront visibles si l'app est un jour distribuée).
- Configuration : « Do not set MetaAppID if you are using Developer Mode » (rappel : Developer Mode OU mode attesté, pas les deux).

## Recommandation
Coder le `VoiceInvocationsStream` quand même (skill `voice-invocations` : stream Wearables-level, pas besoin de DeviceSession ; accuser chaque `LaunchApp` avec `sendSuccess`) et le laisser dormant : le jour où Meta ouvre la permission, ça marche sans rebuild de logique. En attendant, le double tap sur la branche reste le déclencheur mains-libres.
