_Generated: 2026-09-15_
_Neutral documentary questions; no task description is included._

1. Comment les liaisons locales récursives singleton utilisant un type localement abstrait sont-elles représentées dans le Typedtree, notamment lorsque leur RHS immédiat n’est pas Texp_function ?
2. Quelles identités de binders, occurrences d’appel et portées récursives sont actuellement conservées pour ces liaisons dans lib/arch_index/arch_index_cmt.ml ?
3. Comment l’implémentation actuelle détermine-t-elle l’arité syntaxique et le nombre d’arguments effectivement fournis à leurs appels ?
4. Comment les corps de fonctions locaux sont-ils associés aux fonctions synthétiques effectivement stockées, y compris en cas de positions source identiques ?
5. Quelle classification conservative est actuellement produite lorsque l’identité, le corps, l’arité ou le stockage ne peuvent pas être établis sans ambiguïté ?
6. Quelles métadonnées d’appel, de contrôle, d’exception, de canal et de graphe plat accompagnent actuellement ces occurrences dans le corpus Tezos figé identifié par roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv ?
7. [ecosystem] Dans OCaml 5.3.0, quelles formes exactes de Typedtree et d’exp_extra représentent les annotations à types localement abstraits autour d’un corps fonctionnel ?
8. [ecosystem] Quelles garanties documentées OCaml 5.3.0 fournit-il sur Ident, Uid, les positions et l’information d’arité présentes dans les artefacts CMT pour ces constructions ?
