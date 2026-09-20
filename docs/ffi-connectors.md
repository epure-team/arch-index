# FFI connectors

An FFI connector décrit un mécanisme ABI et ses racines source/build/artefacts.
Il fournit de l'évidence de sidecar : jamais une arête de graphe, un résultat
`MUST`, une résolution de callback ou un verdict de sécurité.

## Registry

```json
{"schema_version":1,"connectors":[{"id":"project-ocaml-c","mechanism":"ocaml_c_primitive","version":1,"source_roots":["src/lib"],"build_targets":["src/lib:demo"],"artifact_roots":["_build/default/src/lib"],"enabled":true}]}
```

```sh
node scripts/ffi-connector-registry.js --validate ffi-connectors.json
node scripts/ffi-connector-sidecars.js --registry ffi-connectors.json CORPUS > ffi-sidecars.json
node scripts/ffi-registry-report.js --registry ffi-connectors.json CORPUS > ffi-report.json
```

Le format refuse clés JSON dupliquées, mécanismes/champs inconnus, identifiants
dupliqués et chemins absolus ou sortant du corpus. La configuration borne où
chercher : elle ne peut ni ajouter une regex, ni fournir une preuve, ni élever
une relation possible.

`ocaml_c_primitive` exige external OCaml, primitive C, cible Dune, miroir source
et symbole exact d'artefact. `rust_c_archive_endpoint` exige la chaîne
Rust-C-ABI/archive équivalente. `callback_registration` reste `FRONTIER` : une
inscription ne prouve pas le récepteur.

Les états sont `COMPUTED`, `NOT_ANALYSED`, `REFUSED` et `FRONTIER`. Un résultat
vide ou absent ne prouve jamais l'absence d'une frontière FFI.

## Exécutions récurrentes

```sh
printf '%s\n' '{"version":1,"corpus":"project@REV","artifacts":"build@DIGEST"}' > ffi-scope.json
node scripts/ffi-registry-consumer.js --report ffi-report.json --scope ffi-scope.json --out reviews/base
node scripts/ffi-registry-consumer.js --report ffi-report.json --scope ffi-scope.json --baseline reviews/base/run.json --out reviews/later
```

Le consumer refuse un schéma, registre, corpus/artefacts ou hash de baseline
incompatible. Ses deltas `new`, `changed`, `unchanged`, `absent` sont des faits
de revue — pas des corrections, findings, gates ou verdicts de reachability.

Voir le [contrat détaillé](../specs/ffi-connector-registry.md).
