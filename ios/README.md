# Envol pour iPhone (SwiftUI)

Application native iOS 17+, construite sur les **mêmes données et le même moteur de prix que le site** : la base de 10 000 vols (`../data/flights.csv`), le référentiel et les photos sont embarqués dans l'app. La recherche fonctionne donc **hors ligne** et affiche les mêmes prix que le site.

## Lancer le projet

Il faut un Mac avec Xcode 15 ou plus récent.

```bash
brew install xcodegen
cd ios
xcodegen generate
open Envol.xcodeproj
```

Choisissez ensuite un simulateur iPhone, puis appuyez sur ⌘R.

Avant de régénérer la base avec `node scripts/generate-db.js`, relancez `xcodegen generate` si de nouveaux fichiers ont été ajoutés.

## Premier lancement

Un accueil en 8 écrans apprend à connaître le voyageur :

1. Bienvenue, avec le hublot animé.
2. Prénom, facultatif.
3. Ville de départ : grille de villes avec photos, recherche, ou « Utiliser ma position » pour trouver l'aéroport le plus proche.
4. Envies : mer, villes, culture, nature.
5. Voyageurs : seul, à deux, en famille ou entre amis. Le nombre de passagers est pré-rempli.
6. Budget par vol, cabine, bagage en soute, préférence pour les vols directs.
7. Autorisation des notifications de baisse de prix.
8. Premières suggestions calculées pour ce profil.

Une petite trajectoire, avec un avion, indique la progression. Tout est modifiable ensuite dans l'onglet **Profil**, qui affiche aussi les statistiques : recherches, favoris, alertes. Les données restent sur l'iPhone.

## Fluidité

- La base est chargée en arrière-plan derrière un écran de lancement, et les calculs lourds sont faits hors du fil principal.
- Les prix s'animent chiffre par chiffre et des squelettes s'affichent pendant le chargement.
- Les carrousels sont aimantés et s'animent au défilement ; les boutons s'enfoncent sous le doigt avec un ressort.
- Les transitions d'étape et la trajectoire utilisent des animations à ressort.
- Des retours haptiques accompagnent chaque choix.

## Ce que l'app fait en plus du site

| Fonction | Détail |
|---|---|
| Alertes de baisse de prix | Notifications locales quand un trajet surveillé baisse (vérification à chaque ouverture et en tirant pour rafraîchir). En production : notifications push envoyées par un serveur. |
| Carte Apple Plans | Toutes les destinations depuis une ville, trajets géodésiques, prix sur la carte, fiche en bas d'écran. |
| Gestes | Balayer un vol pour l'ajouter aux favoris, appui long pour le partager, retours haptiques sur les actions clés. |
| Historique des prix | Graphique Swift Charts sur 14 jours pour chaque alerte. |
| Calendrier | Export `.ics` des vols avec rappel d'enregistrement 24 h avant. |
| Accessibilité | VoiceOver (lecture complète de chaque vol, actions personnalisées), Dynamic Type, mode sombre, contrastes système. |

## Structure

| Dossier | Contenu |
|---|---|
| `Envol/Model` | `FlightStore` (lecture de la base, recherche, prix : portage de `js/app.js`), `UserData` (favoris, alertes, préférences), dates |
| `Envol/Views/Search` | Accueil, formulaire, choix d'aéroport, calendrier des prix, voyageurs |
| `Envol/Views/Results` | Résultats (aller puis retour), ligne de vol, filtres |
| `Envol/Views/Detail` | Détail du vol, tarifs, accompagnement jusqu'au site de la compagnie |
| `Envol/Views/Explore` | Carte des destinations |
| `Envol/Views/Saved` | Favoris et alertes |

## Limites connues

- Le code n'a pas pu être compilé ici (environnement Windows, sans Xcode) : prévoyez une passe de corrections mineures à la première compilation.
- Pas encore d'icône d'application (`Assets.xcassets` à ajouter).
- La publication sur l'App Store demande un compte Apple Developer (99 $ par an), des captures d'écran, une politique de confidentialité et la déclaration de confidentialité (« privacy nutrition label »).
