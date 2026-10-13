# Working on sprolog

- Preserve the Lisp-native cons/rational-tree data model and the existing public API.
- Put predicates definable from existing goals in `src/library/standard-library.lisp` as
  ordinary clauses. Do not add a VM instruction just to accelerate a library wrapper.
- Keep executable source forms (`let`, host callbacks, transparent control) in
  the syntax modules. Runtime Prolog terms do not capture Lisp lexical environments.
- Add genuinely stateful operations to the appropriate adapter module; use small
  private `%` boundary operations when validation or database access is unavoidable.
- Register public primitives, syntax, and derived predicates separately. Protect
  all three layers, including aliases, against modification. `clear-database`
  clears user state and must preserve the shared base library.
- Preserve error class, argument validation order, public error context, answer
  order, variable sharing, rational trees, cut scope, and logical update view.
- Dependency packages express ASDF inferred load order; implementation definitions
  retain their symbols in `SPROLOG`. Update dependency packages when moving files.
- For predicate/compiler changes, run `tests/run.lisp` with a 1 MiB control stack.
  Compare `tests/derived-observations.lisp` with the reference revision when changing
  derived definitions. Include cyclic terms, callbacks, SLG, and forced GC where relevant.
- Document conditional retention of adapters in `docs/PRIMITIVES.md`; distinguish
  semantic necessities from optimized or compatibility-preserving implementations.

- Keep source responsibilities in `src/api/`, `src/kernel/`, `src/syntax/`,
  `src/adapters/`, and `src/library/`. Dependency package names must match
  `sprolog/src/<layer>/<file>`. Directory layers share implementation symbols
  and do not imply an acyclic architecture or separately loadable products.
