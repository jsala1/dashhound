# Brief Claude Cowork — commande vocale « Hey Meta, lance Dashhound »

## Contexte

Je suis Julian. Mon app iOS Dashhound (dashcam pour mes Ray-Ban Meta, projet perso) est déjà
déclarée sur le **Wearables Developer Center** : app « Glasses Dashcam », App ID `1559797492031369`,
bundle `com.juliansalaun.glassesdashcam`, Team `Y96VPLGJW7`. Tu l'as créée la dernière fois.

Je veux dire « **Hey Meta, lance Dashhound** » (ou « Hey Meta, start Dashhound ») pour que mes
lunettes préviennent l'app, qui sauvera alors les 45 dernières secondes. Côté Meta, c'est la
capacité expérimentale **Voice Invocations**. Elle se configure dans le Developer Center, **pas**
dans le code. C'est gratuit.

## Ta mission

1. Ouvre <https://wearables.developer.meta.com/> dans le navigateur. **Connexion : c'est moi qui la
   fais**, arrête-toi à l'écran de login. Ne saisis jamais mon mot de passe ni un code 2FA.
2. Ouvre l'app **Glasses Dashcam**.
3. Active la capacité **Voice Invocations** (le nom peut différer légèrement : note le nom réel).
   Si une **demande d'approbation** est nécessaire, remplis-la avec : « Usage personnel : l'utilisateur
   dit "Hey Meta, lance Dashhound" pour sauver les 45 dernières secondes de sa dashcam. Aucune
   donnée envoyée à un tiers, LED de capture visible. »
4. Renseigne le **nom prononcé** de l'app : **Dashhound**. Si plusieurs langues sont proposées :
   français et anglais, même nom.
5. Si on me demande d'**accepter des conditions**, montre-les-moi et **attends mon « ok »**.
6. Au passage, relève le **statut exact** des capacités déjà activées : Camera, Audio Streaming,
   Inputs, Motion.

## Règles

- **Rien de payant.** Si une étape demande un paiement : stop, demande-moi.
- **Ne touche pas** à `Config.xcconfig` ni au Client Token : rien ne change côté identifiants.
- N'invente rien : si l'interface diffère de ce brief, décris ce que tu vois et demande-moi.

## Livrable

Un compte rendu :
- statut de Voice Invocations (actif / en attente de revue / refusé), nom réel de la capacité ;
- nom prononcé enregistré, et langues ;
- statuts de Camera, Audio Streaming, Inputs et Motion ;
- tout avertissement affiché (expérimental, revue, délais).

Claude Code (dans le terminal) branche le code côté app en parallèle.
