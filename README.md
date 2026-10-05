# Tilly

Application de caisse Flutter pour les journees airsoft de Tilly. Elle
permet de gerer une partie depuis un telephone Android, un poste Windows ou
un Mac : inscriptions, ventes, stock, paiements, controle de la caisse et
rapports de fin de journee.

L'application fonctionne hors ligne avec une base SQLite locale. Les services
Firebase et HelloAsso sont optionnels : ils ajoutent respectivement la
synchronisation entre appareils et l'import d'inscrits a un evenement.

## Fonctionnalites

- Gestion de sessions/parties et historique des ventes.
- Liste des joueurs, distinction public/adherent et tarifs adaptes.
- Caisse rapide avec panier, dons et paiements especes, PayPal ou SumUp.
- Onglet repas : preparation a l'avance, suivi a servir/prepare/servi,
  repas HelloAsso ou achete sur place, sauces et notes rapides.
- Catalogue d'articles, locations, stock, seuils d'alerte et mouvements de
  stock.
- Sorties de stock au nom de l'association, sans vente ni paiement.
- Analyse de caisse especes : fond de debut, fond de fin, attendu et ecart.
- Tableau KPI : chiffre d'affaires, produits vendus, alertes stock et
  suggestions de reapprovisionnement.
- Exports PDF : bilan de session, joueurs, analyse de caisse et KPI.
- Export/restauration d'une sauvegarde JSON complete dans le dossier
  `Downloads`.
- Synchronisation manuelle Firebase Auth/Cloud Firestore lorsque configuree.
- Import optionnel d'evenements et de joueurs payants depuis HelloAsso.
- Suivi developpeur Android optionnel avec Firebase Analytics et Crashlytics.
- Verification des mises a jour publiees sur GitHub dans les builds release
  Android, Windows et macOS.
- Licence Tilly par compte (achat a vie pour une version ou abonnement) avec
  activation de l'appareil, fonctionnement hors ligne et gestion des appareils
  depuis le site.

## Plateformes

Les artefacts distribues sont prevus pour :

- Android : fichier APK installable directement.
- Windows x64 : installateur `.exe` ou archive portable `.zip`.
- macOS : image disque `.dmg` ou archive `.zip` contenant `Tilly.app`.

Pour les tags publies avec ce workflow, les liens publics directs vers la
derniere release sont :

- Android APK :
  [Tilly-Android-latest.apk](https://github.com/Kaalister/tilly-app/releases/latest/download/Tilly-Android-latest.apk)
- Windows installateur :
  [TillySetup-latest.exe](https://github.com/Kaalister/tilly-app/releases/latest/download/TillySetup-latest.exe)
- Windows portable :
  [Tilly-Windows-latest.zip](https://github.com/Kaalister/tilly-app/releases/latest/download/Tilly-Windows-latest.zip)
- macOS :
  [Tilly-macOS-latest.dmg](https://github.com/Kaalister/tilly-app/releases/latest/download/Tilly-macOS-latest.dmg)

Ces liens pointent vers les assets de GitHub Release et sont telechargeables
sans compte GitHub lorsque le depot est public. Ne pas partager les liens
`actions/runs/.../artifacts/...` de GitHub Actions : ils peuvent demander une
connexion GitHub. Si la derniere release est anterieure a cette configuration,
utiliser les fichiers versionnes depuis la page
[Releases GitHub](https://github.com/Kaalister/tilly-app/releases/latest).

L'interface est responsive : navigation basse et ecran vertical sur mobile,
navigation laterale et panneaux multiples sur tablette ou ecran large.

## Installation Utilisateur

### Android

1. Telecharger le dernier fichier
   `Tilly-Android-<version>.apk` depuis la page
   [Releases GitHub](https://github.com/Kaalister/tilly-app/releases/latest).
2. Ouvrir le fichier APK sur le telephone.
3. Autoriser l'installation d'applications provenant de cette source si
   Android le demande, puis installer l'application.
4. Lancer **Tilly**.

Les donnees sont stockees localement sur le telephone. Pour changer d'appareil,
utiliser **Config > Exporter** puis **Restaurer**, ou configurer Firebase.

### Mettre A Jour Sans Perte De Donnees

Une mise a jour doit remplacer l'installation existante, sans la
desinstaller et sans effacer ses donnees :

- Android : ouvrir le nouvel APK et choisir l'installation/mise a jour de
  l'application deja presente. L'identifiant `com.tilly.caisse` et la
  signature de publication doivent rester identiques.
- Windows : executer le nouvel installateur dans le meme emplacement. Il
  remplace les fichiers du programme sans supprimer les donnees utilisateur
  stockees hors du dossier d'installation.
- macOS : ouvrir le nouveau DMG et remplacer `Tilly.app` dans Applications.
  Les donnees restent dans le dossier Application Support de l'utilisateur.
- Depuis l'ecran de mise a jour de l'application, une sauvegarde JSON de
  recuperation est automatiquement creee dans `Downloads` avant l'ouverture
  du fichier a telecharger.

Dans ce scenario, la base SQLite locale n'est pas supprimee, Firebase Auth
conserve la session de l'utilisateur et le secret HelloAsso reste dans le
stockage securise de l'appareil. Une desinstallation, un effacement des
donnees Android ou l'utilisation d'une autre signature APK ne constitue pas
une mise a jour et ne permet pas cette conservation.

### Windows

1. Telecharger `TillySetup-<version>.exe` depuis la page
   [Releases GitHub](https://github.com/Kaalister/tilly-app/releases/latest).
2. Executer l'installateur et suivre l'assistant.
3. Lancer **Tilly** depuis le menu Demarrer ou le raccourci
   cree pendant l'installation.

L'archive `Tilly-Windows-<version>.zip` est disponible pour un
usage portable : extraire tout le dossier puis executer
`tilly.exe`.

### macOS

1. Telecharger `Tilly-macOS-<version>.dmg` depuis la page
   [Releases GitHub](https://github.com/Kaalister/tilly-app/releases/latest).
2. Ouvrir l'image disque et glisser **Tilly** dans **Applications**.
3. Lancer **Tilly** depuis le dossier Applications.

L'archive `Tilly-macOS-<version>.zip` contient egalement `Tilly.app`.
Tant que la signature Developer ID et la notarisation Apple ne sont pas
configurees dans le workflow, macOS peut demander de confirmer le premier
lancement via clic droit sur l'application, puis **Ouvrir**.

## Utilisation

1. Creer une nouvelle session depuis l'historique ou selectionner la session
   active.
2. Ajouter ou importer les joueurs, puis saisir les achats depuis l'ecran
   caisse.
3. Configurer les articles et le stock dans l'ecran de configuration des
   tarifs.
4. Saisir les fonds de caisse debut/fin et consulter l'analyse especes.
5. Exporter les bilans PDF et une sauvegarde JSON avant archivage ou transfert
   vers un autre appareil.

### Licence et activation

L'application demande une licence liee au compte de l'association
(https://tilly.orceus.fr). Au premier lancement, saisir l'e-mail et le mot de
passe du compte puis cliquer sur **Se connecter** : l'appareil est active.

- **Licence a vie** : achetee pour une version precise (par exemple 2.1). Elle
  fonctionne hors ligne sans limite de duree ; les versions ulterieures ne sont
  pas couvertes.
- **Abonnement** : couvre toutes les versions tant qu'il est actif et autorise
  30 jours de fonctionnement hors ligne avant revalidation.

Etats particuliers :

- **Version non couverte** : l'app est en lecture seule (donnees consultables et
  exportables) et propose de telecharger la version couverte.
- **Appareil desactive** : message avec **Ouvrir mon compte** ; la reactivation
  se fait uniquement depuis le site.
- **Abonnement hors ligne** : bandeau **Se connecter** pour revalider.
- **Limite d'appareils atteinte** (5 par defaut) : gerer les appareils depuis le
  site.

Dans **Config > Compte**, le bouton **Se deconnecter** retire le compte de
l'appareil sans toucher aux donnees. Chaque compte Tilly possede ses propres
donnees locales : changer de compte change les donnees affichees. La
desactivation d'un appareil ne peut pas etre faite depuis l'application.

Le guide association est detaille dans
[`documentation/MISE_EN_PLACE.md`](documentation/MISE_EN_PLACE.md).

### Firebase, optionnel

Sans connexion Firebase, l'application reste utilisable avec sa base locale.
Une fois Firebase configure et un utilisateur connecte dans **Config**, le
bouton **Synchroniser** envoie ou recupere un snapshot de la base. Une
recuperation Firebase plus recente exige une confirmation et cree auparavant
une sauvegarde locale de securite. Aucun transfert ne se fait au demarrage.

La procedure de creation et de configuration Firebase est detaillee dans
[`documentation/FIREBASE_SETUP.md`](documentation/FIREBASE_SETUP.md).

### Firebase monitoring developpeur, optionnel

Le suivi des crashs et des utilisateurs actifs utilise un Firebase separe de
la synchronisation configurable dans l'application. Il se configure au moment
du build Android avec le `google-services.json` du projet monitoring, sans
ecran de saisie dans l'application.

La procedure est detaillee dans
[`documentation/FIREBASE_MONITORING_SETUP.md`](documentation/FIREBASE_MONITORING_SETUP.md).

### Firebase monitoring developpeur, optionnel

Le suivi des crashs et des utilisateurs actifs utilise un Firebase separe de
la synchronisation configurable dans l'application. Il se configure au moment
du build Android avec le `google-services.json` du projet monitoring, sans
ecran de saisie dans l'application.

La procedure est detaillee dans
[`documentation/FIREBASE_MONITORING_SETUP.md`](documentation/FIREBASE_MONITORING_SETUP.md).

### HelloAsso, optionnel

Dans **Config > HelloAsso**, renseigner le slug de l'association, un client ID,
un secret API et l'environnement (production ou sandbox). Lors de la creation
d'une session, l'application peut alors lier un evenement HelloAsso et importer
les payeurs inscrits. Le secret est conserve dans le stockage securise de
l'appareil et est exclu des exports JSON et de Firebase.

## Donnees Locales

La base SQLite contient notamment :

| Donnee | Usage |
| --- | --- |
| Sessions | Parties, dates et lien evenement HelloAsso |
| Joueurs | Public/adherent et presence par session |
| Articles et categories | Prix, prix adherent, stock et seuils |
| Ventes et lignes de vente | Panier valide, moyen de paiement et snapshots |
| Repas | Origine, statut, formule, boisson/snack inclus et indications |
| Mouvements de stock | Historique des variations |
| Comptages de caisse | Fonds de debut et de fin par denomination |
| Parametres | Session active, HelloAsso et metadonnees de synchronisation |

Les locations restent facturables mais ne consomment jamais de stock. Une
consommation interne peut etre enregistree dans **Articles & prix > Sortie
asso** ; elle diminue le stock et alimente les statistiques sans generer de
paiement ni de chiffre d'affaires.

En mode developpement, la base et le snapshot Firebase utilisent un suffixe
`_dev` afin de ne pas ecraser les donnees de production.

## Dependances

### Prerequis de developpement

- Flutter avec Dart `>=3.3.0 <4.0.0`.
- Android Studio ou le SDK Android pour executer/compiler Android.
- Pour compiler Windows : Windows avec Visual Studio et la charge de travail
  **Desktop development with C++**.
- Pour produire l'installateur Windows : Inno Setup 6.
- Pour compiler macOS : un Mac avec Xcode complet, les outils en ligne de
  commande Xcode et CocoaPods.

### Paquets Flutter principaux

| Package | Role |
| --- | --- |
| `sqflite` | Stockage SQLite sur Android |
| `sqflite_common_ffi` | Stockage SQLite sur Windows et macOS |
| `path` et `path_provider` | Emplacement de la base et des fichiers exportes |
| `pdf` | Generation des rapports PDF |
| `firebase_core` | Initialisation Firebase |
| `firebase_auth` | Connexion email/mot de passe pour la synchronisation |
| `cloud_firestore` | Stockage du snapshot synchronise |
| `firebase_analytics` | Mesure d'usage Android pour le Firebase developpeur |
| `firebase_crashlytics` | Remontee des crashs Android pour le Firebase developpeur |
| `http` | Appels API HelloAsso et controle des Releases GitHub |
| `flutter_lints` et `flutter_test` | Analyse statique et tests |

Les versions exactes se trouvent dans [`pubspec.yaml`](pubspec.yaml).

## Installation Developpeur

### Recuperer et lancer le projet

```bash
git clone https://github.com/Kaalister/tilly-app.git
cd tilly-app
flutter doctor
flutter pub get
```

Pour Android, demarrer un emulateur ou brancher un appareil avec le debogage
USB active, puis :

```bash
flutter devices
flutter run -d <device-id>
```

Pour Windows, executer ces commandes depuis un poste Windows :

```powershell
flutter config --enable-windows-desktop
flutter run -d windows
```

Pour macOS, executer ces commandes depuis un Mac :

```bash
flutter config --enable-macos-desktop
flutter run -d macos
```

Firebase n'est pas requis pour lancer l'application. Dans **Config > Firebase**,
le bouton **Activer Firebase** permet de coller la configuration du projet et
de connecter le compte utilisateur dans un seul parcours. Les paramètres sont
conservés dans le stockage sécurisé de l'appareil. Activer Firebase
Authentication par email/mot de passe et Cloud Firestore comme expliqué dans
[`documentation/FIREBASE_SETUP.md`](documentation/FIREBASE_SETUP.md).

### Configuration de l'API de licence

L'URL de base de l'API de licence est lue depuis un fichier `.env` embarque
avec l'application :

| Fichier | Build | Valeur par defaut |
| --- | --- | --- |
| `.env.dev` | debug (`flutter run`) | `http://localhost:3000` |
| `.env` | profile et release | `https://tilly.orceus.fr` |

Pour tester la production depuis un build debug, modifier `.env.dev`. A
l'inverse, ne jamais placer l'URL locale dans `.env` : ce fichier est embarque
dans les builds de release, donc dans les APK, ZIP et DMG distribues.

Si le fichier est absent ou illisible, l'application retombe sur les valeurs
compilees dans `lib/src/config/app_config.dart`.

#### Backend local selon la plateforme

- macOS, Windows et Linux : `http://localhost:3000` fonctionne tel quel.
- Emulateur Android : `localhost` designe l'emulateur, pas le Mac. En debug,
  l'application remplace automatiquement `localhost` et `127.0.0.1` par
  `10.0.2.2` (adresse de la machine hote vue par l'emulateur). Le trafic HTTP
  en clair est autorise uniquement dans le manifest debug.
- Appareil Android physique : renseigner l'adresse locale du poste de
  developpement dans `.env.dev`, par exemple
  `LICENSE_API_URL=http://192.168.1.128:3000`, puis reconstruire l'application.
  Le telephone et le poste doivent etre sur le meme reseau.

Une modification de `.env.dev` necessite un redemarrage complet de
l'application (`flutter run`), pas un simple hot reload.

### Verification

```bash
flutter analyze --no-fatal-infos
flutter test
```

### Builds locaux

```bash
flutter build apk --release
flutter build windows --release
flutter build macos --release
```

Le build APK release signe necessite un keystore Android et un fichier local
`android/key.properties`. Le monitoring Android peut etre ajoute avec
`android/app/google-services.json`, comme explique dans
[`documentation/FIREBASE_MONITORING_SETUP.md`](documentation/FIREBASE_MONITORING_SETUP.md).
Le build Windows doit etre execute depuis Windows et le build macOS depuis
un Mac equipe de Xcode et CocoaPods.

## Publication Des Releases

Le workflow [`.github/workflows/windows-release.yml`](.github/workflows/windows-release.yml)
construit les artefacts lors d'un tag SemVer prefixe par `v`, par exemple
`v1.1.2` :

- APK Android signe ;
- archive portable Windows ;
- installateur Windows Inno Setup ;
- image disque et archive macOS.

Pour la signature Android, les secrets GitHub Actions suivants doivent etre
configures :

| Secret | Contenu |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Keystore Android encode en base64 |
| `ANDROID_STORE_PASSWORD` | Mot de passe du keystore |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la cle |
| `ANDROID_KEY_ALIAS` | Alias de signature |

Pour le monitoring Android, ajouter aussi le secret
`TILLY_MONITORING_GOOGLE_SERVICES_JSON_BASE64` indique dans
[`documentation/FIREBASE_MONITORING_SETUP.md`](documentation/FIREBASE_MONITORING_SETUP.md).

Le keystore et son alias constituent l'identite de l'application installee.
Ils doivent etre archives et reutilises pour toutes les releases Android :
Android refuse une mise a jour signee avec une autre cle. Ne jamais changer
non plus `applicationId = "com.tilly.caisse"` pour une release de mise
a jour, sous peine d'installer une deuxieme application sans acces aux donnees
locales de la precedente.

Sur macOS, le keystore peut etre encode avant ajout dans GitHub avec :

```bash
base64 -i android/app/tilly-release.jks | pbcopy
```

## Structure Du Depot

| Chemin | Contenu |
| --- | --- |
| `lib/main.dart` | Point d'entree et assemblage des modules |
| `lib/src/controllers/` | Orchestration de la caisse et regles metier |
| `lib/src/data/`, `lib/src/services/` | SQLite, Firebase, HelloAsso et secrets |
| `lib/src/ui/`, `lib/src/exports/` | Ecrans, dialogues et exports PDF |
| `android/` | Projet Android |
| `windows/` | Projet Windows |
| `macos/` | Projet macOS |
| `installer/` | Script Inno Setup pour l'installateur Windows |
| `.github/workflows/` | Compilation et publication automatique |
| `documentation/` | Documentation Firebase, analyse et references PDF/HTML |
| `test/` | Tests Flutter |

L'application est issue de la reference fonctionnelle et graphique conservee
dans `documentation/Base/caisse_airsoft.html`. L'analyse correspondante se
trouve dans [`documentation/ANALYSE_HTML.md`](documentation/ANALYSE_HTML.md).
