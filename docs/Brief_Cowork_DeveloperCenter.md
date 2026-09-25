# Brief Claude Cowork — app « Glasses Dashcam » sur le Wearables Developer Center

## Contexte

Je suis Julian. Projet perso : une app iOS (`~/Projects/glasses-dashcam`) qui transforme mes
Ray-Ban Meta en dashcam rétroactive. La phase 0 est validée. Pour la phase 1, j'ai besoin que
l'app soit déclarée sur le **Wearables Developer Center de Meta**, pour avoir le **son du micro des
lunettes** (capacité expérimentale « Audio Streaming ») et, plus tard, le **bouton de capture** et
l'**IMU** des lunettes (« Inputs », « Motion »). C'est **gratuit**.

## Ta mission

1. Ouvre <https://wearables.developer.meta.com/> dans le navigateur.
2. **Connexion : c'est moi qui la fais.** Arrête-toi à l'écran de login et dis-moi « à toi pour la
   connexion ». Ne saisis jamais mon mot de passe ni un code 2FA.
3. Si on me demande d'**accepter des conditions** (developer terms, AUP) : montre-les-moi et
   **attends mon « ok »**. Ne coche rien à ma place.
4. Crée un projet/app nommé **Glasses Dashcam** (plateforme **iOS**), avec :
   - Bundle ID iOS : `com.juliansalaun.glassesdashcam`
   - Apple Team ID : `Y96VPLGJW7`
   - Description courte si demandée : « Usage personnel : dashcam rétroactive (45 s en mémoire) à partir
     du flux caméra des lunettes. LED de capture visible, pas de publication. »
5. Active ces capacités, si elles existent sous ces noms (sinon, note les noms réels) :
   **Camera**, **Audio Streaming** (ou microphone), **Inputs**, **Motion**.
6. Si mon compte ou mes lunettes doivent être ajoutés comme **testeur / release channel** pour
   utiliser l'app hors Developer Mode, fais-le, ou dis-moi ce qu'il faut que je fasse.
7. Récupère l'**App ID** (`MetaAppID`) et le **Client Token**.

## Règles

- **Rien de payant.** Si une étape demande un paiement ou une carte : stop, demande-moi.
- **Le Client Token est un secret.** Ne le colle dans aucun chat, mail, doc partagé ou outil en
  ligne. Écris-le **uniquement** dans le fichier local ci-dessous.
- N'invente rien : si l'interface diffère de ce brief, décris ce que tu vois et demande-moi.

## Livrable

1. Crée le fichier `~/Projects/glasses-dashcam/Config.xcconfig` (il est déjà exclu de git), avec
   exactement ce contenu :

   ```
   // Identifiants Wearables Developer Center — NE PAS COMMITTER (gitignoré)
   META_APP_ID = <App ID>
   CLIENT_TOKEN = <Client Token>
   ```

2. Réponds-moi avec un compte rendu **sans le Client Token** :
   - App ID (celui-là n'est pas secret) ;
   - capacités activées, avec leur statut exact (actif / en attente de revue / refusé) ;
   - ce qui a été fait pour le testeur / release channel ;
   - tout avertissement affiché (capacité expérimentale, limites, revue Meta).

Claude Code (dans le terminal) prendra ensuite le relais : il branchera `Config.xcconfig` dans le
projet Xcode et lancera le test A/B du son.
