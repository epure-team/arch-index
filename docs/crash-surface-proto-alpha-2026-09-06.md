> **Jugé peu actionnable en l'état par son destinataire, et conservé avec cette critique
> plutôt que retouché.** Ce qu'il manque, par ordre de rendement : **(1) aucun chemin témoin** —
> `escaping-origins` donne un site et aucune route vers lui, alors que les chemins témoins sont
> livrés (roadmap 1.5) et que `arch-rules` en imprime ; sans eux on ne distingue pas « un handler
> RPC atteint ce site » de « seule l'application de bloc y va », qui est l'axe rendant un crash
> actionnable. **(2) Aucune classification de la garde au site** — `assert false` contre
> `assert <cond>`, diviseur littéral contre variable : c'est ce tri qui a produit l'unique
> trouvaille, et il a été fait **à la main**, pas par l'outil. **(3) Aucun rang** — la trouvaille
> est noyée au milieu de 175 lignes triées par nom de fichier. Les trois sont petits ; le premier
> est du câblage.

# Qu'est-ce qui peut faire crasher le protocole ?

**Corpus :** `proto_alpha/lib_protocol`, build `/home/mathias/dev/tezos/tezos/_build/default`,
500 `.cmt`. **Index reconstruit maintenant** (468 modules, 14 452 fonctions, 73 939 appels), pas
réutilisé d'hier. Outil : `arch-query escaping-origins --roots exported`, binaire construit sur
`6930d3c` (un commit derrière `main` `090f832`, qui ne touche pas le producteur).

## Ce que le rapport est, et ce qu'il n'est pas

    root: exported (3011 entry points)
    coverage: 5282 nodes reached · 13519 edges unresolved · 2369 ⊤ — LOWER BOUND

**BORNE INFÉRIEURE, et c'est la ligne la plus importante du rapport.** Le cône part des 3 011
points d'entrée exportés et atteint 5 282 nœuds sur 14 452. Les 9 170 autres ne sont pas
« prouvés inatteignables » : la fermeture **s'arrête à chaque arête non résolue**, et il y en a
13 519, dont 2 369 marquées ⊤. Un site de crash situé derrière une de ces arêtes n'apparaît pas
ici. La liste est un plancher, jamais un inventaire.

**Un seul canal.** `channel exception` — les origines sur les canaux `option`, `tzresult` et
`result` ne sont pas rapportées. Un échec qui remonte en `Error` plutôt qu'en exception est hors
champ de ce passage.

## Le décompte

**217 sites** atteignables depuis la surface exportée.

| | total | dont production (hors `test/`) |
|---|---|---|
| `assert` | 118 | **87** |
| `division` | 76 | **67** |
| `index` (accès hors bornes) | 23 | **21** |
| **total** | **217** | **175** |

La colonne `reach` du rapport (127 MUST / 90 MAY) qualifie **le chemin vers le site**, pas la
probabilité du crash : MUST veut dire « ce site est atteint sur un chemin d'appels prouvé », pas
« ce site plante ».

## Le décompte n'est pas la trouvaille

**Les 87 `assert` de production se scindent en deux populations qui n'ont rien à voir :**

- **51 sont `assert false`** — une branche déclarée impossible par l'auteur. Ce n'est pas une
  vérification, c'est une annotation. Elle plante si le raisonnement de l'auteur est faux, ce
  qu'aucune analyse de ce type ne peut décider.
- **35 sont `assert <condition>`** — une assertion sur une valeur : `assert (Compare.Int.(i >= 0))`
  dans `cycle_repr`, `assert (Compare.Z.(total_size >= Z.zero))` dans `contract_storage`,
  `assert (Operation_hash.equal first_hash last_hash)` dans `contract_repr`. Celles-là dépendent de
  données.

**Les divisions sont dominées par des diviseurs qui ne peuvent pas être nuls.** `tez_repr` en
concentre 13, le module le plus dense — et ce sont toutes des divisions par `1000L`, `10`, `100`
dans du code d'affichage. `percentage.ml` en a 5, dont 4 par la constante `precision_factor`.

*(J'ai tenté un classement automatique littéral/expression : il donne 19/43, mais le filtre est
grossier — il classe `Int64.div amount 1000L` comme une expression. Je ne le présente pas comme
une mesure.)*

La vraie classe de diviseurs variables est **les constantes de protocole** : `block_time`,
`blocks_per_cycle`, `era.blocks_per_commitment`, `slots_per_chunk`, `first_round_duration`,
`max_active_levels`. Cohérent avec ce qui avait été trouvé plus tôt : de l'arithmétique sur des
constantes de protocole, pas des entrées/sorties.

## La trouvaille : division par un dénominateur de `Ratio_repr`

`Ratio_repr` est un enregistrement **public** :

    ratio_repr.mli:26   type t = {numerator : int; denominator : int}

et l'invariant `denominator > 0` n'est imposé **qu'au décodage** :

    ratio_repr.ml:33-34  if Compare.Int.(denominator > 0) then Ok {numerator; denominator}
                         else Error "The denominator must be greater than 0."

Quatre sites de production divisent par ce dénominateur. **Trois sont protégés, un ne l'est pas,
et la différence est structurelle :**

| site | d'où vient le ratio | protégé ? |
|---|---|---|
| `delegate_missed_attestations_storage.ml:147` | `Constants_storage.minimal_participation_ratio ctxt` | oui — les constantes arrivent par l'encoding |
| `delegate_missed_attestations_storage.ml:259` | idem | oui |
| `delegate_missed_attestations_storage.ml:349` | idem | oui |
| **`percentage.ml:44`** — `of_ratio_bounded` | **son appelant, quel qu'il soit** | **non** |

`percentage.mli:18` expose `val of_ratio_bounded : Ratio_repr.t -> t`. La fonction déstructure et
divise sans garde locale :

    percentage.ml:44   of_int_bounded (one_hundred_percent * numerator / denominator)

Donc : **une fonction publique qui lève `Division_by_zero` sur une valeur que son type autorise**,
protégée uniquement par un chemin — l'encoding — que son appelant n'est pas obligé d'emprunter.

**Ce n'est pas un bug vivant.** Le seul appelant dans l'index est
`test/unit/test_percentage.ml::pct_of_int`. C'est un trou au niveau du type sur une fonction
exportée : rien n'empêche un futur appelant de construire le ratio à la main.

## Ce que ce rapport ne peut pas voir

1. **Tout ce qui est derrière les 13 519 arêtes non résolues.** C'est la borne inférieure, et
   c'est de loin la plus grosse limite.
2. **Les autres canaux d'erreur.** `option` / `tzresult` / `result` non parcourus ici.
3. **La justesse des 51 `assert false`.** Aucune analyse de ce type ne décide si une branche
   déclarée impossible l'est.
4. **Les dépassements arithmétiques et l'épuisement mémoire**, qui ne sont pas des « origines
   fatales » au sens de cet index.
