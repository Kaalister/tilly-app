# TODO mise en place et evolutions

Ce fichier liste uniquement ce qu'il reste a relire ou modifier pour vendre
l'application avec un tuto de mise en place simple : installation + Firebase.

Derniere mise a jour : 2026-09-11 (agents assigned).

## Agent Assignments
- **senior-flutter**: CI fixes, ListTile/Material, version alignment
- **senior-android**: Keystore, Redmi T10 testing, Firebase monitoring
- **senior-ios**: macOS DMG testing, future iOS/PWA
- **firebase-engineer**: Sync Firebase config, monitoring, rules
- **data-engineer**: SQLite migrations, backup/restore, stock
- **ui-ux-engineer**: Mobile cart, Tiko tutorial, responsive, ListTile fix
- **platform-integration-engineer**: HelloAsso, PDF, GitHub updates, tilly-platform
- **release-engineer**: CI/CD, versioning, artifacts, signing secrets
- **qa-engineer**: Test strategy, CI alignment, device matrix
- **secretary**: Auto-updates this file, AGENTS.md, README, docs
- **reviewer**: Read-only reviews, blocks push on violations
- **tech-writer**: MISE_EN_PLACE.md, user guides, non-tech testing

## Documentation a relire

- [ ] `documentation/MISE_EN_PLACE.md`
  - Verifier les etapes Android.
  - Verifier les etapes Windows.
  - Verifier les etapes Firebase Console.
  - Ajouter des captures d'ecran si besoin.
  - Verifier que le guide reste simple et ne part pas sur de la documentation
    inutile.

## Modifications necessaires avant de vendre ce modele

### Firebase configurable dans l'application

- [x] Ne plus imposer un Firebase compile dans l'application.
- [x] Ajouter un parcours `Activer Firebase` dans la configuration.
- [x] Permettre de renseigner :
  - [x] `apiKey`
  - [x] `appId`
  - [x] `projectId`
  - [x] `messagingSenderId`
  - [x] `authDomain`
  - [x] `storageBucket`
  - [x] `measurementId`
- [x] Accepter le collage d'un bloc Web `firebaseConfig`.
- [x] Accepter le collage du contenu Android `google-services.json`.
- [x] Conserver la saisie champ par champ dans les options avancees.
- [x] Enregistrer cette configuration dans le stockage securise local.
- [x] Exclure cette configuration des sauvegardes et de la synchronisation.
- [x] Initialiser Firebase depuis cette configuration locale.
- [x] Tester la configuration pendant l'activation avec la connexion du compte.
- [x] Reunir la configuration du projet et la connexion utilisateur dans un seul
      parcours.
- [x] Ajouter une action `Reinitialiser Firebase`.
- [x] Afficher clairement que Firebase est optionnel.

### Chemin Firestore generique

- [x] Supprimer le chemin code en dur contenant `tilly`.
- [x] Choisir le chemin final pour la V1 :

```txt
organizations/default/users/{userId}/snapshots/caisse-main
```

- [x] Mettre a jour les regles Firestore du tuto selon le chemin choisi.

### Utilisation multi-appareils

- [x] V1 : recommander un seul compte Firebase partage par association dans le
      guide de mise en place.
- [ ] Afficher cette recommandation dans l'application, par exemple dans l'aide
      Firebase ou dans le parcours `Activer Firebase`.
- [ ] V2 eventuelle : gerer plusieurs comptes dans une meme association.

### Onboarding minimal

- [x] Ajouter un premier ecran qui explique que Firebase est optionnel.
- [x] Ajouter un acces direct via l'onglet `Config > Firebase`.
- [x] Ajouter une aide Firebase lorsque le compte n'est pas connecte, avec un
      lien vers le tutoriel complet.
- [x] Ajouter une sauvegarde JSON avant mise a jour depuis l'ecran de mise a
      jour.
- [x] Ajouter une sauvegarde JSON avant restauration Firebase ou fichier.
- [x] Ajouter la mention dans le tuto : outil de suivi non certifie.
- [x] Afficher dans l'application une mention courte : outil de suivi non
      certifie.

### Version web app pour iOS

- [ ] Prevoir une version web/PWA de l'application pour iPhone et iPad.
- [ ] Permettre l'installation depuis Safari via `Ajouter a l'ecran d'accueil`.
- [ ] Ajouter un manifest web avec nom, icones, couleur et mode plein ecran.
- [ ] Ajouter les icones iOS necessaires.
- [ ] Verifier le fonctionnement en mode standalone sur iOS.
- [ ] Adapter le stockage local pour le web.
- [ ] Verifier la compatibilite Firebase sur web.
- [ ] Verifier les limites iOS pour l'usage hors ligne et la persistance locale.
- [ ] Adapter les exports PDF et JSON pour le navigateur.
- [ ] Ajouter une section dans le tuto de mise en place pour l'installation iOS
      lorsque la version web sera disponible.
- [ ] Tester sur iPhone et iPad reels.

### Version macOS desktop

- [x] Ajouter la cible macOS au projet Flutter.
- [x] Utiliser le plugin SQLite natif `sqflite_darwin` sur macOS sans remplacer
      sa factory par la factory FFI.
- [x] Verifier le lancement en mode debug.
- [x] Verifier visuellement l'affichage et la navigation de l'application.
- [x] Verifier la persistance des reglages et l'acces a la base SQLite locale.
- [x] Produire et lancer un build macOS release universel Intel et Apple Silicon.
- [x] Ajouter la creation des archives ZIP et DMG au workflow GitHub Actions.
- [x] Verifier que l'archive ZIP est integre et que l'application extraite
      conserve une signature interne valide.
- [x] Verifier que le DMG est integre, montable et contient `Tilly.app` ainsi
      que le raccourci vers `Applications`.
- [x] Retenir une distribution gratuite sans certificat Apple payant, signature
      `Developer ID` ni notarisation.
- [x] Documenter l'installation depuis le DMG non signe et la procedure macOS
      `Reglages Systeme > Confidentialite et securite > Ouvrir quand meme`.
- [x] Preciser qu'il ne faut ni desactiver Gatekeeper ni utiliser une commande
      Terminal pour installer Tilly.
- [x] Documenter le remplacement de l'application sans perte des donnees
      locales.
- [ ] Tester l'installation et la mise a jour depuis le DMG sur un deuxieme Mac.

### Personnalisation

- [x] Ajouter un onglet `Config > Personnalisation` en premier dans la
      configuration.
- [x] Ajouter une option pour changer l'icone affichee dans l'application depuis
      une image.
- [x] Ajouter une option pour changer le nom de l'association.
- [x] Ajouter une option pour changer la couleur primaire du theme de
      l'application.
- [x] Ajouter une option pour afficher/cacher les onglets `Repas`, `Joueurs`,
      `Caisse`, `Stats`, `Bilan` et `Articles`.
- [x] Ajouter une option pour desactiver le module repas et masquer ses
      mentions dans l'application.
- [x] Prevoir une personnalisation par association dans les reglages de
      l'application.

### Branding generique

- [x] Choisir le nom commercial final.
- [x] Mettre a jour les exports PDF si le nom apparait dedans.

### HelloAsso

- [x] Garder HelloAsso en place comme prevu.
- [x] Ajouter une aide HelloAsso tant que la connexion n'est pas configuree,
      avec un lien vers le tutoriel complet.
- [x] Verifier que le secret HelloAsso n'est pas synchronise dans Firebase.
- [x] Verifier que le secret HelloAsso n'est pas inclus dans les exports JSON.
- [x] Ajouter un message simple si la connexion HelloAsso echoue.

## Verifications avant publication

- [ ] Relire `documentation/MISE_EN_PLACE.md`.
- [ ] Faire tester le tuto par une personne non technique.
- [ ] Verifier que l'app permet vraiment de configurer Firebase depuis
      l'interface.
- [ ] Faire un test complet avec un nouveau projet Firebase.
- [ ] Installer l'app sur un deuxieme appareil et recuperer les donnees via
      Firebase.
- [ ] Faire une sauvegarde JSON avant et apres le test.
- [ ] Verifier que la mention "outil non certifie" est visible.

## Mettre en place un suivit

- [x] connecter mon firebase perso pour suivre les metrique de l'applications : crash, nombre d'utilisateurs etc ...
