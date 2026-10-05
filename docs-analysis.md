# Analyse de la source et décisions d'import

Source : *Bible minceur*, Hugo Blanc, document fourni de 261 pages, édition PDF produite le 28 mai 2019. Empreinte SHA-256 : `549f8cd2949ab16a23958132861a8183c82418f6153d176e1675dd349aba6107`.

## Inventaire

| Catégorie | Recettes | Utilisation par défaut |
|---|---:|---|
| Petit-déjeuner | 24 | Hors planning déjeuner/dîner |
| Boissons | 7 | Hors planning déjeuner/dîner |
| Déjeuner | 24 | Déjeuner |
| Salades | 19 | Déjeuner et dîner |
| Vinaigrettes | 6 | Accompagnements consultables |
| Dîner | 56 | Dîner |
| Collations | 10 | Hors planning déjeuner/dîner |
| **Total** | **146** | |

99 recettes sont candidates pour les déjeuners et dîners. L'import produit 146 JPEG et 1 231 lignes d'ingrédients après retrait d'une ligne de matériel. Les parties théoriques et les menus types du début du livre ne sont pas utilisés comme règles de génération.

## Provenance et fidélité

Les numéros imprimés et les positions du PDF diffèrent d'une page : la page imprimée 176 est la page PDF 177. Les deux sont stockés. La table des matières donne les titres canoniques ; certaines pages emploient un titre légèrement différent. Les recettes sur deux pages réunissent la photo, les ingrédients et les étapes.

Les ingrédients conservent le texte brut et un composant lorsqu'un sous-titre est identifiable. Quantités et unités sont interprétées sans conversion de masse ou volume. Les plages et quantités ambiguës restent manuelles. Les aliments sont classés par un dictionnaire explicite ; cette classification n'est pas une validation humaine. Les variantes sont extraites partiellement selon les blocs identifiables et ne sont pas automatiquement appliquées.

Les photos sont les images existantes du PDF, sélectionnées automatiquement selon leur surface sur les pages de la recette. Leur association par page est vérifiable, mais le livre peut employer des illustrations dont les ingrédients ne correspondent pas exactement à la recette ; une relecture visuelle complète reste à faire.

## Points à relire

Six recettes ont des numérotations qui ne forment pas une seule suite : `bm-180`, `bm-192`, `bm-197`, `bm-198`, `bm-199`, `bm-222`. Plusieurs redémarrages correspondent à un composant séparé (purée, compote, salade ou sauce), tandis que `bm-180` présente une étape 2 là où une étape 5 serait attendue. Le numéro source est préservé ; l'ordre réel est déterminé par la position des étapes.

Treize recettes ont plusieurs durées explicites dans les métadonnées. `total_minutes` en fait la somme conservatrice ; `source_duration_text` garde le libellé initial et `summed_time_components` le signale. Des préparations simultanées pourraient réduire ce temps. Les durées simples restent celles du livre et peuvent ne pas refléter toutes les attentes décrites dans les étapes.

`bm-091` indique une nuit au réfrigérateur et 10 minutes de préparation. La durée totale reste inconnue (`null`) et `unquantified_overnight_wait` le signale ; un filtre de durée maximale l'exclut. Aucune durée de nuit n'est inventée.

Les recettes peuvent mentionner une préparation composée (vinaigrette, pesto, sauce de soja, pâte de curry, pain, etc.) sans sa composition exhaustive. Les exclusions et le filtre végétarien ne peuvent contrôler que les ingrédients explicitement identifiables. En particulier, exclure `porc` seul ne supprime pas automatiquement `jambon`, `bacon`, `salami` ou `saucisse` : sélectionner aussi ces identifiants selon le besoin.

Les valeurs kcal du livre sont conservées sans recalcul. Il n'y a pas de valeurs protéines/glucides/lipides fiables ni de saisonnalité, prix ou conservation structurés. Aucune valeur n'est inventée pour combler ces absences.

## Périmètre de cette version

Application Flutter, moteur et API optionnelle en Dart, photos embarquées, base SQLite sur Android/iOS/macOS et sauvegarde du dernier planning via shared_preferences sur web. Les exclusions sont strictes et les créneaux non satisfaits sont signalés. Le générateur classe les candidats selon la présence des aliments préférés et limite les répétitions ; il ne fait pas d'optimisation nutritionnelle ou de coût et n'impose pas de répartition hebdomadaire par type de protéine.

À préciser pour la prochaine version : nombre habituel de personnes, temps de préparation, exclusions précises, place du dessert, saisonnalité souhaitée et synchronisation entre appareils.
