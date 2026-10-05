# Mise en place de l'application

Ce guide explique uniquement comment installer l'application et configurer
Firebase pour qu'une association puisse utiliser sa propre synchronisation.

L'application est fournie deja compilee. L'association n'a pas besoin de
compiler Flutter ni d'utiliser GitHub Actions.

## 1. Installer l'application

### Android

1. Recuperer le fichier APK fourni.
2. Ouvrir le fichier APK sur le telephone ou la tablette.
3. Si Android le demande, autoriser l'installation depuis cette source.
4. Installer l'application.
5. Ouvrir l'application.

### Windows

1. Recuperer l'installateur Windows fourni.
2. Lancer le fichier `.exe`.
3. Si Windows affiche une alerte SmartScreen, verifier que le fichier vient
   bien du vendeur, puis continuer l'installation.
4. Ouvrir l'application depuis le menu Demarrer ou le raccourci cree.

### macOS

La version macOS de Tilly est distribuee gratuitement sans signature
`Developer ID` ni notarisation Apple. Elle reste installable, mais macOS ne
peut pas verifier l'identite du developpeur et bloque son premier lancement.

#### Installer Tilly

1. Recuperer l'image disque `Tilly-macOS-<version>.dmg` depuis la source
   officielle communiquee par le vendeur.
2. Ouvrir le fichier `.dmg`.
3. Glisser **Tilly** sur le raccourci **Applications** affiche dans l'image
   disque.
4. Ouvrir le dossier **Applications** et essayer de lancer **Tilly** une
   premiere fois.
5. Si macOS indique que le developpeur ne peut pas etre verifie ou qu'Apple ne
   peut pas rechercher les logiciels malveillants, fermer le message.
6. Ouvrir **Reglages Systeme > Confidentialite et securite**.
7. Descendre jusqu'a la section **Securite**, puis cliquer sur
   **Ouvrir quand meme** pour Tilly.
8. Saisir le mot de passe ou utiliser Touch ID si macOS le demande, puis
   confirmer avec **Ouvrir**.

Cette confirmation ne concerne que le premier lancement de cette copie de
Tilly. Les lancements suivants se font normalement depuis **Applications**.
Ne jamais contourner cet avertissement si le DMG ne provient pas de la source
officielle. Il n'est pas necessaire de desactiver Gatekeeper ni d'executer une
commande dans le Terminal.

Procedure Apple officielle :

https://support.apple.com/en-euro/guide/mac-help/mh40616/mac

## 2. Mettre a jour l'application

Pour conserver les donnees :

1. Ouvrir l'application actuelle.
2. Exporter une sauvegarde JSON depuis l'ecran de configuration.
3. Installer la nouvelle version par-dessus l'ancienne.
4. Ne pas desinstaller l'application.
5. Ne pas effacer les donnees de l'application.

## 3. Activer Tilly avec votre compte

Depuis la version 2, Tilly demande une licence pour fonctionner. La licence est
liee au compte de l'association cree sur https://tilly.orceus.fr.

### 3.1 Premier lancement

1. Installer l'application (voir la section 1).
2. Au premier ecran, saisir l'e-mail et le mot de passe du compte Tilly de
   l'association.
3. Cliquer sur `Se connecter`.
4. L'application active l'appareil et affiche l'ecran d'accueil.

Une fois active, l'application fonctionne hors ligne. Internet n'est necessaire
que pour la premiere activation, la revalidation d'un abonnement et la
verification des appareils autorises.

### 3.2 Deux types de licence

- **Licence a vie** : achetee pour une version precise (par exemple 2.1).
  L'application fonctionne hors ligne sans limite de duree. Les versions
  ulterieures ne sont pas couvertes.
- **Abonnement** : couvre toutes les versions pendant la duree de l'abonnement.
  Sans connexion, l'application continue de fonctionner pendant une fenetre de
  grace de 30 jours, puis demande une connexion pour verifier que l'abonnement
  est toujours actif.

### 3.3 Appareils

Le compte inclut un nombre d'appareils autorises (5 par defaut). Chaque appareil
est identifie par un identifiant unique cree au premier lancement : il reste le
meme tant que l'application est installee.

La gestion des appareils et de l'abonnement se fait uniquement depuis le site :
https://tilly.orceus.fr/compte

### 3.4 Messages affiches par l'application

- **Version non couverte** : une licence a vie achetee pour la version 2.1
  n'autorise pas la version 2.5. L'application passe en lecture seule : les
  donnees restent visibles et exportables, mais aucune operation de caisse n'est
  possible. Il faut revenir a la version couverte ou faire evoluer la licence.
- **Appareil desactive** : l'appareil a ete retire depuis le site. L'application
  propose `Ouvrir mon compte` pour le reactiver. La reactivation n'est possible
  que depuis le site.
- **Connexion Internet necessaire** : la fenetre hors ligne de l'abonnement est
  depassee. L'application reste consultable en lecture seule et le bouton
  `Se connecter` revalide la licence.
- **Limite d'appareils atteinte** : trop d'appareils utilisent ce compte.
  Utiliser `Ouvrir mon compte` pour en liberer un.

### 3.5 Se deconnecter

Dans `Config > Compte`, le bouton `Se deconnecter` retire le compte de cet
appareil. Les donnees de l'association restent enregistrees localement.

Chaque compte Tilly possede ses propres donnees locales sur l'appareil : en
changeant de compte, l'application affiche les donnees de ce compte. Pour
retrouver les donnees du compte precedent, il suffit de se reconnecter avec lui.

La desactivation d'un appareil (retrait definitif) se fait uniquement depuis le
site Tilly, jamais depuis l'application.

## 4. Comprendre Firebase

Firebase est optionnel.

Sans Firebase, l'application fonctionne en local sur l'appareil.

Avec Firebase, l'association peut :

- synchroniser les donnees entre plusieurs applications ;
- recuperer les donnees sur un autre appareil ;
- utiliser plusieurs appareils avec le meme compte Firebase.

Le modele prevu est simple : chaque association cree son propre projet Firebase
et utilise son propre compte.

Pour une premiere version, il est recommande d'utiliser un seul compte Firebase
partage par association.

Deux informations sont demandees pendant l'activation :

- la configuration du projet indique a l'application quel projet Firebase
  utiliser ;
- l'email et le mot de passe autorisent l'acces aux donnees de ce projet.

L'application reunit ces deux etapes dans un seul ecran. La configuration du
projet n'est pas un deuxieme mot de passe.

## 5. Creer le projet Firebase

1. Aller sur https://console.firebase.google.com/
2. Cliquer sur `Ajouter un projet`.
3. Donner un nom au projet, par exemple `caisse-mon-association`.
4. Desactiver Google Analytics si l'association n'en a pas besoin.
5. Terminer la creation du projet.

Le plan gratuit Firebase peut suffire pour un usage associatif simple, selon
les quotas Firebase en vigueur. Les tarifs et limites doivent toujours etre
verifies sur la page officielle :

https://firebase.google.com/pricing

## 6. Activer l'authentification

1. Dans Firebase Console, ouvrir `Authentication`.
2. Cliquer sur `Commencer`.
3. Ouvrir `Sign-in method`.
4. Activer `Email/Password`.
5. Enregistrer.

Documentation officielle :

https://firebase.google.com/docs/auth/flutter/password-auth

## 7. Creer le compte de l'association

1. Aller dans `Authentication > Users`.
2. Cliquer sur `Ajouter un utilisateur`.
3. Saisir l'email de l'association.
4. Choisir un mot de passe fort.
5. Conserver l'email et le mot de passe dans un endroit sur.

Ce compte servira a se connecter dans l'application.

## 8. Activer Firestore

1. Dans Firebase Console, ouvrir `Firestore Database`.
2. Cliquer sur `Creer une base de donnees`.
3. Choisir le mode production si Firebase le propose.
4. Choisir une region proche de l'association.
5. Terminer la creation.

## 9. Configurer les regles Firestore

Dans `Firestore Database > Rules`, coller des regles limitees a l'utilisateur
connecte.

Exemple pour la version simple :

```txt
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /organizations/default/users/{userId}/snapshots/{snapshotId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId
                         && snapshotId in ['caisse-main', 'caisse-dev'];
    }
  }
}
```

Cliquer ensuite sur `Publier`. Sans cette action, les nouvelles regles ne sont
pas utilisees par Firebase. Attendre une minute avant le premier essai si les
regles viennent d'etre remplacees.

Le mot `default` est une valeur litterale utilisee par Tilly. Il ne faut pas le
remplacer par le nom du projet Firebase ou de l'association.

Ces regles signifient qu'un compte Firebase ne peut lire et ecrire que ses
propres donnees et uniquement dans les snapshots `caisse-main` et `caisse-dev`.

Documentation officielle :

https://firebase.google.com/docs/firestore/security/get-started

## 10. Recuperer la configuration Firebase

La configuration depend de la plateforme. Android, Windows et macOS
appartiennent au meme projet Firebase, mais utilisent des applications
Firebase differentes.

### 10.1 Android

1. Revenir a la vue d'ensemble du projet Firebase.
2. Cliquer sur `Ajouter une application`, puis sur l'icone Android.
3. Saisir exactement le package :

```txt
com.tilly.caisse
```

4. Choisir un surnom libre, par exemple `Caisse Android`.
5. Laisser le certificat SHA vide.
6. Enregistrer l'application.
7. Telecharger `google-services.json`.
8. Ouvrir le fichier avec un editeur de texte et copier tout son contenu.

Il ne faut pas ajouter le fichier dans l'APK ni modifier Gradle : l'application
de caisse est deja compilee et lit directement le contenu colle.

Le fichier reste disponible dans `Parametres du projet > General > Vos
applications`.

Documentation officielle :

https://firebase.google.com/docs/android/setup

### 10.2 Windows

Firebase ne propose pas d'application Windows dans ce parcours. La caisse
Windows utilise une application Firebase Web.

1. Revenir a la vue d'ensemble du projet Firebase.
2. Cliquer sur `Ajouter une application`, puis sur l'icone Web `</>`.
3. Choisir un surnom libre, par exemple `Caisse Windows`.
4. Ne pas activer Firebase Hosting.
5. Enregistrer l'application.
6. Reperer puis copier le bloc complet :

```js
const firebaseConfig = {
  apiKey: "...",
  authDomain: "...",
  projectId: "...",
  storageBucket: "...",
  messagingSenderId: "...",
  appId: "..."
};
```

Il n'est pas necessaire d'executer les commandes `npm` proposees. Le bloc reste
disponible dans `Parametres du projet > General > Vos applications >
Configuration du SDK`.

Documentation officielle :

https://firebase.google.com/docs/web/setup

### 10.3 macOS

La caisse macOS utilise une application Firebase Apple.

1. Revenir a la vue d'ensemble du projet Firebase.
2. Cliquer sur `Ajouter une application`, puis sur l'icone Apple.
3. Saisir exactement le bundle ID `com.tilly.caisse`.
4. Choisir un surnom libre, par exemple `Caisse macOS`.
5. Enregistrer l'application et telecharger `GoogleService-Info.plist`.
6. Ouvrir ce fichier avec un editeur de texte et copier tout son contenu.

## 11. Renseigner Firebase dans l'application

Dans l'application :

1. Ouvrir `Config > Firebase`.
2. Cliquer sur `Activer Firebase`.
3. Cliquer sur `Coller`, ou coller manuellement le contenu correspondant a la
   plateforme : `google-services.json` sur Android ou `firebaseConfig` sur
   Windows, ou `GoogleService-Info.plist` sur macOS.
4. Saisir l'email et le mot de passe crees dans Firebase.
5. Cliquer sur `Activer`.
6. Verifier que l'etat indique `Synchronisation active`.
7. Cliquer sur `Synchroniser`.

La saisie champ par champ reste disponible dans `Options avancees`, mais elle
n'est normalement pas necessaire.

### 11.1 Verifier la premiere synchronisation

1. Verifier que l'application indique `Donnees envoyees vers Firebase` ou
   `Donnees deja synchronisees`.
2. Dans Firebase Console, ouvrir `Firestore Database > Data`.
3. Verifier la presence du chemin :

```txt
organizations/default/users/{uid}/snapshots/caisse-main
```

Une version de developpement utilise `caisse-dev` au lieu de `caisse-main`.

La synchronisation est manuelle et porte sur un snapshot complet. Tilly envoie
la version locale lorsqu'elle est la plus recente, ou propose de remplacer les
donnees locales lorsqu'un autre appareil a envoye une version plus recente.
Les modifications ne sont pas fusionnees ligne par ligne.

## 12. Utiliser un autre appareil

1. Installer l'application sur le nouvel appareil.
2. Utiliser la configuration adaptee a sa plateforme : configuration Android
   pour Android, configuration Web pour Windows.
3. Se connecter avec le meme compte Firebase.
4. Cliquer sur `Synchroniser`.
5. Si Firebase contient des donnees plus recentes, confirmer la restauration.
6. Verifier que les donnees ont ete recuperees.

Avant une restauration depuis Firebase, faire une sauvegarde JSON si
l'application le propose.

Ne pas travailler sur deux appareils en meme temps. Synchroniser avant de
changer d'appareil, puis synchroniser de nouveau apres les modifications.

### 12.1 Erreurs courantes

`Configuration non reconnue` : recopier le bloc `firebaseConfig` complet ou le
contenu complet de `google-services.json`.

`Email ou mot de passe incorrect` : verifier que Email/Password est active et
que l'utilisateur existe dans `Authentication > Users`.

`Acces Firestore refuse` : verifier que les regles ont ete collees dans le
projet Firebase configure dans Tilly, que le chemin contient exactement
`organizations/default/users` sans remplacer `default`, puis cliquer sur
`Publier`.

`Aucune donnee` : verifier que le premier appareil a deja synchronise et que
les deux appareils utilisent le meme compte Firebase.

## 13. Configurer HelloAsso

HelloAsso permet d'importer les evenements et les participants payants dans
l'application.

La configuration HelloAsso demande 4 informations :

- `Organization slug`
- `Client ID`
- `Client secret`
- environnement : `Production` ou `Sandbox`

Pour une association en utilisation reelle, choisir `Production`.

### 13.1 Trouver l'organization slug

L'`Organization slug` correspond a l'identifiant public de l'association dans
les URL HelloAsso.

Exemple :

```txt
https://www.helloasso.com/associations/mon-association
```

Dans cet exemple, le slug est :

```txt
mon-association
```

On peut le retrouver :

1. en ouvrant la page publique HelloAsso de l'association ;
2. en regardant l'URL apres `/associations/` ;
3. ou dans les liens publics des formulaires et evenements HelloAsso.

### 13.2 Trouver le Client ID et le Client secret

1. Se connecter au compte HelloAsso de l'association.
2. Dans le menu de gauche, ouvrir `Mon compte`.
3. Ouvrir `Integrations et API`.
4. Creer la cle API si aucune cle n'existe encore.
5. Copier le `Client ID`.
6. Copier le `Client secret` et le conserver dans un gestionnaire de mots de
   passe.

Une cle creee depuis le compte d'une association donne acces aux donnees de
cette association. Si la rubrique n'apparait pas, verifier que le compte
connecte dispose bien des droits d'administration de l'association.

Documentation officielle :

https://dev.helloasso.com/docs/obtenir-une-cl%C3%A9-api

### 13.3 Renseigner HelloAsso dans l'application

Dans l'application :

1. Ouvrir `Config`.
2. Aller dans la section `HelloAsso`.
3. Ouvrir `Configuration HelloAsso`.
4. Renseigner `Organization slug`.
5. Renseigner `Client ID`.
6. Renseigner `Client secret`.
7. Choisir `Production`.
8. Enregistrer.
9. Cliquer sur le bouton de test de connexion HelloAsso si disponible.

Si la connexion fonctionne, l'application doit pouvoir afficher les evenements
HelloAsso lors de la creation d'une session.

### 13.4 Utiliser HelloAsso pendant la creation d'une session

1. Creer une nouvelle session dans l'application.
2. Choisir l'evenement HelloAsso a lier.
3. Importer les participants.
4. Verifier que les joueurs ou inscrits apparaissent correctement.

### 13.5 Securite du secret HelloAsso

Le `Client secret` doit rester confidentiel.

Ne pas le publier :

- dans un depot GitHub ;
- dans une capture d'ecran ;
- dans une documentation publique ;
- dans un message partage a des personnes non autorisees.

Le secret HelloAsso ne doit pas etre synchronise dans Firebase et ne doit pas
etre inclus dans les exports JSON.

## 14. Limite importante

L'application est un outil de suivi de caisse associative.

Elle n'est pas un logiciel de caisse certifie et ne remplace pas les
obligations comptables ou fiscales de l'association.
