# Envol — comparateur de vols (démo)

Site de recherche de vols « le prix d'abord », 100 % front-end, avec une base texte de **10 000 vols modélisés sur les réseaux réels des compagnies**, et une **application iPhone native** (dossier `ios/`) qui utilise la même base.

## Lancer

Ouvrez `index.html` dans un navigateur (double-clic). Aucun serveur ni dépendance nécessaire.
Optionnel : `npx serve .` pour servir le dossier en HTTP (active aussi le manifeste d'application web).

Pour régénérer la base : `node scripts/generate-db.js` (déterministe : la base est identique à chaque exécution).
Application iPhone : voir `ios/README.md`.

## Structure

| Fichier | Rôle |
|---|---|
| `index.html` | Structure des vues, icônes SVG, encart de l'app iPhone |
| `css/style.css` | Styles (inspiration Apple, un seul bleu d'action) |
| `js/app.js` | Moteur de recherche, prix, filtres, parcours aller-retour et réservation, carte Explorer, favoris, alertes, aide |
| `data/reference.js` | 61 aéroports, 48 compagnies (alliances, bases, ponctualité, frais de bagage), profils saisonniers, vacances scolaires |
| `scripts/network.js` | Routes directes réelles de chaque compagnie, par base |
| `scripts/generate-db.js` | Générateur de la base (horaires, durées, correspondances, tarifs de base) |
| `data/flights.csv` | **La base de données texte** : 10 000 vols (1 ligne = 1 vol régulier ou 1 itinéraire avec correspondance) |
| `data/flights.js` | Copie de la base pour l'ouverture en `file://` |
| `data/reference.json`, `data/photos.json` | Mêmes données au format JSON pour l'app iOS |
| `data/photos.js` | Une photo Unsplash par destination (sélection manuelle) |
| `data/world.js` | Fond de carte Natural Earth pré-projeté (SVG), sans dépendance |
| `ios/` | Application SwiftUI (iOS 17+) |
| `JURIDIQUE.md` | Questions juridiques : APIs, redirection ou réservation directe, photos, logos |

## La base de 10 000 vols

Elle n'est pas aléatoire : elle est **construite à partir des réseaux réels** des 48 compagnies.

- **Routes.** Environ 1 600 liaisons directes réellement exploitées, entre les 61 aéroports du site : Air France depuis CDG et Orly, easyJet depuis ses bases, Emirates depuis Dubaï…
- **Horaires.** Vagues réalistes :
  - Europe → Amérique du Nord en fin de matinée, retours de nuit ;
  - Europe → Asie le midi ou le soir ;
  - hubs du Golfe la nuit ;
  - low-cost tôt le matin.

  Chaque compagnie a sa propre banque horaire. Les jours d'opération dépendent de la ligne.
- **Durées.** Distance orthodromique, vents dominants d'ouest (Paris → New York en 8 h 20, retour en 7 h 20) et contournement de l'espace aérien russe vers Tokyo et Séoul (environ 14 h).
- **Correspondances.** Elles sont construites en appariant les vrais horaires aux hubs (même compagnie ou même alliance), avec un temps minimum de correspondance par aéroport (CDG 70 min, FRA 50 min, JFK 90 min…).
- **Flottes et numéros de vol.** Flotte réelle de chaque compagnie (A350 et 777 chez Air France, A380 chez Emirates, 737 chez Ryanair…). Les numéros suivent les conventions des compagnies (aller pair, retour impair). Quelques numéros réels sont repris : AF006, AF011, BA117, LH400, KL641…
- **Prix.** Le tarif de base dépend de la distance, du type de compagnie et de la concurrence sur la ligne. Le prix affiché varie ensuite selon plusieurs facteurs :
  - la saison de la destination (Méditerranée en été, Caraïbes en hiver, Japon au printemps…) ;
  - les vacances scolaires françaises et Thanksgiving ;
  - l'anticipation, avec une courbe différente pour le court et le long-courrier ;
  - le jour et l'heure de départ ;
  - le remplissage du vol ce jour-là.

  Les low-cost affichent des prix en « …9 € ».

> Ce sont des données **modélisées sur la réalité**, pas des horaires officiels : les heures exactes et les prix ne correspondent pas aux vols réellement en vente. En production, ils viendraient d'une API (voir `JURIDIQUE.md`).

### Format de `flights.csv` (séparateur `;`)

`id;al;fn;from;to;via;dep;dur;lay;days;ac;price;cab;hold;meal;wifi;pwr;refund;co2;ontime;ld`

- `fn` : numéros de vol (`AF1234+AF276` en cas de correspondance) ; `via` : aéroports d'escale.
- `dep` : heure de départ locale, en minutes ; `dur` : durée totale ; `lay` : durées d'escale ; `ld` : durée de chaque tronçon.
- `days` : jours d'opération, du lundi au dimanche (`1111100`).
- `ac` : appareil de chaque tronçon, séparé par `|`.
- `price` : tarif de base en €.

## Fonctionnalités

- **Recherche.** Autocomplétion au clavier (villes multi-aéroports PAR / LON, « Partout »), calendrier avec le prix de chaque jour, recherches récentes.
- **Parcours aller / retour.** Bandeau d'étapes : l'étape en cours est cerclée de bleu, l'aller validé affiche son vol et son prix, et le total aller-retour se met à jour.
- **Résultats.**
  - codes aéroport et villes ;
  - prix des jours voisins, avec les flèches ← → ;
  - **grille aller × retour sur 7 × 7 jours** ;
  - tris Recommandé / Moins cher / Plus rapide ;
  - conseil prix avec la raison (haute saison, vacances…) ;
  - vue liste ou frise horaire.
- **Prix avec bagage.** Ajoute le vrai coût d'un bagage en soute aux tarifs qui ne l'incluent pas, pour comparer low-cost et compagnies classiques à armes égales.
- **Filtres** (panneau latéral) : escales, prix, horaires, durée, bagages, compagnies, alliances, correspondances, confort, conditions.
- **Détail et réservation.**
  - itinéraire tronçon par tronçon ;
  - alerte de visa de transit (escale aux États-Unis, au Canada ou au Royaume-Uni) ;
  - tarifs Light / Standard / Flex ;
  - vérifications avant de réserver ;
  - redirection vers le ou les sites des compagnies ;
  - **ajout au calendrier (.ics) avec rappel 24 h avant**.
- **Aide.** Visite guidée en 4 étapes à la première recherche, bouton « ? » avec raccourcis clavier et lexique (Recommandé, +1, billets séparés, CO₂…), infobulles sur les termes.
- **Explorer.** Carte du monde, trajets depuis la ville de départ, prix sur la carte, filtres mois, envie, budget et direct.
- **Et aussi.** Favoris avec suivi du prix, alertes avec historique sur 14 jours, comparateur (3 vols), partage par lien, 6 devises, responsive, bannière de l'app sur mobile, `prefers-reduced-motion`.

**Raccourcis clavier :** `/` nouvelle recherche · `F` filtres · `←` `→` jour précédent ou suivant · `?` aide · `Échap` fermer.

Les logos sont chargés depuis des CDN publics (pics.avs.io, puis images.kiwi.com), avec en repli un monogramme aux couleurs de la compagnie. Voir `JURIDIQUE.md` avant toute mise en ligne.
