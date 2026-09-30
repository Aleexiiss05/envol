# Envol — cadre juridique d'un comparateur de vols (France / UE)

> Synthèse pour orienter les choix techniques et commerciaux. **Ce n'est pas un avis juridique** : faites valider le modèle retenu par un avocat en droit du tourisme et du numérique avant le lancement. Les offres des fournisseurs d'API changent souvent : vérifiez leurs conditions actuelles.

---

## 1. Ai-je le droit d'aller chercher des vols ?

### Oui, via des API sous contrat. Non (ou très risqué), par scraping.

**Aspirer (scraper) les sites des compagnies, Google Flights, Skyscanner, etc.** expose à :

- **La violation des CGU** du site. La CJUE (*Ryanair c/ PR Aviation*, C-30/14, 15 janvier 2015) admet qu'un site peut interdire contractuellement l'extraction de ses données, même lorsqu'elles ne sont pas protégées par le droit des bases de données.
- **Le droit *sui generis* du producteur de bases de données** (directive 96/9/CE ; art. L.341-1 et L.342-1 du Code de la propriété intellectuelle) : l'extraction d'une partie substantielle est interdite.
- **L'accès frauduleux à un système informatique** (art. 323-1 et s. du Code pénal) si vous contournez des protections (captchas, blocages d'IP, etc.).
- Des contentieux réels : Ryanair, par exemple, poursuit depuis des années les agences et outils qui aspirent son site.

**Les sources légales, du plus simple au plus engageant :**

| Source | Ce qu'elle permet | Modèle | Remarques |
|---|---|---|---|
| **Travelpayouts / Aviasales** | Données de prix (en cache) + liens affiliés | Redirection, commission | Gratuit, accessible aux petits sites : idéal pour démarrer |
| **Skyscanner Partners** | Recherche en temps réel, deep links | Redirection, affiliation | Sur candidature, souvent réservé aux sites qui ont déjà du trafic |
| **Kiwi.com (Tequila)** | Recherche, combinaisons, réservation | Redirection ou réservation | Accès restreint aux partenaires B2B |
| **Amadeus for Developers** | Recherche, prix, réservation | Les deux | Le portail *Self-Service* a annoncé sa fermeture : vérifiez son statut. Sinon, Amadeus Enterprise sous contrat |
| **Duffel** | Recherche **et** réservation (NDC + GDS), émission des billets | Réservation sur votre site | Duffel porte l'émission : vous n'avez pas besoin de l'accréditation IATA |
| **Sabre, Travelport** (GDS) | Inventaire complet | Réservation | Contrats lourds, pensés pour les agences accréditées |
| **API NDC des compagnies** (Air France-KLM, Lufthansa Group…) et **programmes d'affiliation** (Awin, CJ…) | Offres et liens directs | Les deux | Au cas par cas, sur accord de la compagnie |

Les services qui scrapent Google Flights (du type SerpApi) relèvent d'une **zone grise** : déconseillés pour un produit commercial.

---

## 2. Rediriger vers la compagnie, ou réserver sur mon site ?

Les deux sont possibles, mais **ce ne sont pas du tout les mêmes métiers juridiques.**

### Modèle A — Méta-moteur avec redirection (Skyscanner, Google Flights, Kayak)

C'est le modèle de la démo : l'utilisateur paie sur le site de la compagnie ou de l'agence partenaire. Vous êtes rémunéré au clic (CPC) ou à la vente (commission d'affiliation).

- **En principe, pas d'immatriculation Atout France**, puisque vous ne vendez pas le voyage.
- **Obligations qui restent :**
  - **Mentions légales** (LCEN, art. 6), CGU, politique de confidentialité.
  - **RGPD** : registre des traitements, bases légales, contrats avec les sous-traitants. **Cookies et traceurs** : les liens d'affiliation et les pixels de suivi exigent le consentement préalable (recommandations CNIL).
  - **Plateforme en ligne / comparateur** (Code de la consommation, art. L.111-7 et D.111-7 et s.) : information loyale, claire et transparente sur les **critères de classement** et sur l'existence d'une **rémunération** qui influence ce classement. Tout placement payant doit être signalé comme « annonce » ou « sponsorisé ». Si vous affichez « aucun placement payant », il faut que ce soit vrai.
  - **Prix** : le règlement (CE) 1008/2008, art. 23, impose d'afficher **à tout moment le prix final**, taxes, redevances et suppléments inévitables compris. Les options facultatives (assurance, siège…) se font en *opt-in*. La CJUE applique ces règles aux intermédiaires (*ebookers.com*, C-112/11).
  - **Pratiques commerciales trompeuses** (art. L.121-2 C. conso) et **interfaces trompeuses** (*dark patterns*, art. 25 du DSA) :
    - « Le moins cher », « plus que 3 places », « prix bas » ou les prédictions de prix doivent reposer sur des **données réelles et vérifiables**.
    - Dans la démo, ces indicateurs sont simulés : **à brancher sur de vraies données ou à retirer avant la mise en ligne.**
  - **DSA** (règlement (UE) 2022/2065) : point de contact et mécanisme de signalement. **Règlement P2B** (2019/1150) vis-à-vis des professionnels référencés.
  - **Accessibilité** : l'**European Accessibility Act**, applicable depuis le 28 juin 2025, vise notamment le commerce électronique et les services de transport de passagers. Le site devra viser la conformité RGAA / WCAG 2.1 AA.

### Modèle B — Agence en ligne qui vend sur son site (Booking, Opodo, eDreams)

Le client paie **chez vous**, et vous transmettez la réservation à la compagnie. Vous devenez **vendeur de services de voyage** :

- **Immatriculation au registre des opérateurs de voyages** tenu par **Atout France** (Code du tourisme, art. L.211-18), avec :
  - une **garantie financière** (APST, organisme bancaire ou assureur) ;
  - une **assurance de responsabilité civile professionnelle**.

  La vente de vols « secs » relève en principe de ce régime en France. Le périmètre exact (transport seul, forfaits, prestations liées) est à valider avec un conseil.
- **Émission des billets** : elle passe par l'**accréditation IATA** (BSP, garanties financières importantes), ou par un intermédiaire qui émet pour vous (consolidateur, **Duffel**, etc.).
- **Paiement** : prestataire de paiement (Stripe, Adyen…), **PCI-DSS**, authentification forte **DSP2 / 3-D Secure**. N'encaissez pas pour le compte de tiers sans vérifier le statut d'agent de paiement.
- **Droit de la consommation** :
  - CGV ;
  - **pas de droit de rétractation** pour un transport à date déterminée (art. L.221-28, 12°), à indiquer clairement ;
  - **médiateur de la consommation** obligatoire (art. L.612-1) ;
  - si vous vendez aussi hôtel ou voiture : **forfaits et prestations de voyage liées** (directive (UE) 2015/2302 ; art. L.211-2 et s.) avec **responsabilité de plein droit** (art. L.211-16).
- **Après-vente** : annulations, changements d'horaires, remboursements, relais des réclamations au titre du **règlement (CE) 261/2004**. L'indemnisation reste due par le transporteur, mais le client s'adresse d'abord à vous.
- **Données passagers** (identité, passeport, parfois données sensibles comme l'assistance PMR) : sécurité et RGPD renforcés.

### Recommandation

1. **Lancer en méta-moteur (modèle A)**, avec l'affiliation Travelpayouts ou Skyscanner et les programmes des compagnies. Risque et coût minimes, et c'est exactement le parcours de la démo : on accompagne l'utilisateur jusqu'au deep link de la compagnie.
2. Si le trafic le justifie, **passer à la réservation intégrée** avec Duffel (ou équivalent), **après** l'immatriculation Atout France, la garantie financière et l'assurance RC pro.

---

## 3. Logos, marques et nom du site

- Les **logos et noms des compagnies sont des marques déposées**. Les utiliser pour **identifier** la compagnie dont on présente le vol est en général admis (usage de référence : art. L.713-6 CPI ; art. 14 du règlement (UE) 2017/1001). C'est à condition de ne suggérer **aucun partenariat ni parrainage** et de ne pas modifier les logos.
- Dans la démo, les logos viennent de CDN tiers (pics.avs.io, images.kiwi.com). En production, utilisez les **logos fournis sous licence par votre partenaire d'API** ou obtenez l'autorisation des compagnies.
- **Photographies** : issues d'Unsplash (licence Unsplash : usage commercial gratuit, sans attribution obligatoire, mais interdiction de revendre les photos telles quelles ou de reconstituer un service concurrent). La récupération par `scripts/fetch-photos.js` passe par l'interface interne du site : en production, utilisez l'**API officielle Unsplash** (clé, règles de *hotlinking* et d'attribution) ou hébergez vos propres visuels sous licence.
- **Fond de carte** : Natural Earth, domaine public.
- **« Envol » est un nom provisoire** : vérifiez sa disponibilité (INPI, EUIPO, noms de domaine) avant tout dépôt.

---

## 4. La base de 10 000 vols

- Elle est **modélisée sur la réalité** : les routes, flottes, alliances, vagues horaires, durées et saisons sont réalistes, et quelques numéros de vol sont réels. En revanche, **les horaires exacts et les prix ne correspondent pas aux vols réellement en vente**.
- Plus les données ressemblent à de vraies offres, plus le risque de confusion est grand. **Ne publiez pas ces données comme de vraies offres** :
  - afficher un faux prix pour un vrai vol d'une vraie compagnie (par exemple « AF006 à 407 € ») serait une pratique commerciale trompeuse (art. L.121-2 C. conso) ;
  - la compagnie pourrait aussi y voir une atteinte à sa marque.
- La mention « démonstration, données simulées » doit rester visible tant que les données ne viennent pas d'une API sous contrat.
- Pour construire une base réelle d'horaires, les sources licites sont :
  - les fichiers **SSIM** des compagnies (horaires planifiés, sous licence) ;
  - des fournisseurs de données comme **OAG** ou **Cirium** (payants) ;
  - ou, plus simplement, l'API de votre partenaire de recherche (voir la section 1).

## 5. L'application iPhone

- **Publication.** Il faut un compte Apple Developer (99 $ par an) et respecter les *App Review Guidelines*. Un comparateur qui redirige vers des sites tiers est accepté. S'il vend des billets dans l'app, les services réels sont payés hors achat intégré, mais le vendeur doit être clairement identifié.
- **Confidentialité.**
  - Déclarez les données collectées (« privacy nutrition label »), avec une politique de confidentialité en ligne.
  - Si vous ajoutez des outils de suivi (analytics, affiliation), il faut demander l'autorisation *App Tracking Transparency*.
  - Le RGPD s'applique comme sur le site.
- **Notifications.** Ne les utilisez pas pour de la publicité sans consentement explicite : les alertes de prix demandées par l'utilisateur sont admises.
- **Badge « App Store ».** L'encart de la page d'accueil n'utilise pas le badge officiel d'Apple. Le jour où l'app est publiée, utilisez le badge officiel en respectant les règles d'identité d'Apple.

---

*Dernière mise à jour : septembre 2026. Ces textes évoluent : vérifiez les versions en vigueur sur Légifrance et EUR-Lex.*
