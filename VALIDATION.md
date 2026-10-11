# Validation — 0.9.0, 2026-10-12

SBCL 2.2.9.debian, Linux x86-64. No external Lisp libraries.

```sh
sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
```

4,141 checks pass with a 1 MiB Lisp control-stack limit.
The sole execution backend is granular WAM. The earlier reference backend and
its selectable API are removed. The suite includes WAM-only GC comparisons and
the builtin, term-model and DCG syntax regressions.

| Stress case | Result | Max VM continuation depth | Max managed heap cells |
|---|---|---:|---:|
| 1,000,000 deterministic tail calls | Pass | 1 | 4,096 |
| 100,000 non-tail calls | Pass | 100,001 | 100,000 |
| 100,000 tail iterations constructing/discarding compound terms | Pass | 2 | 65 |
| Compile/unify/export a 100,000-element list | Pass | Iterative traversal | Input-sized live terms |
| Parse 10,000 tokens with a right-recursive DCG | Pass | 1 | 13,079 |
| Expand a 10,000-level nested DCG AND expression | Pass | Iterative expansion | Source-sized work list |

The million-call run allocates 1,000,000 managed cells and reclaims 998,936 before
its first answer. The garbage-producing run allocates 800,000 cells, reclaims
799,967 and has a maximum post-GC live set of 8 cells. These are VM ownership-cell
statistics, not process RSS or total Lisp allocation measurements.

The DCG recursion stress case retains 10,001 choice points because its epsilon
alternative exists at every recursive level. GC correctly preserves those
alternatives. Bounded tail continuation depth does not imply bounded search memory.

## Semantic and GC coverage

- Original core unification, clause order, recursion, cut, rollback and lexical host tests.
- 96 independently varied queries compared with GC disabled vs thresholds 1, 8, 64.
- All eighteen term instructions executed through actual S-expression source programs.
- Cyclic terms/source graphs, forced GC between answers, scan roots and cursor release.
- DCG parsing and generation, semantic trees, empty rules, repeated/compound tokens,
  PHRASE/2 full consumption and PHRASE/3 residual input.
- Nested sequences, nested/multiple alternatives and relocated branch addresses in
  non-first clauses; prefix side effects execute once across branch alternatives.
- Predicate-local cuts, pruning grammar clause alternatives, and opaque PHRASE
  expression cut scope preserving caller choices, including forced GC.
- Embedded semantic goals, lexical Lisp callbacks, runtime Lisp PHRASE, hidden
  generated variables, rule replacement and malformed/cyclic grammar rejection.
- DCG answers compared with independent hand-written difference-list rules with
  automatic GC disabled and enabled.

These are regression tests and observed execution results, not a formal proof or
an Allegro/ISO conformance suite. The append, DCG and SLG standalone examples also pass.

## SLG and well-founded semantics coverage

- Cyclic transitive closure with the left-recursive clause first, mutual recursion,
  positive loops without a base, nonground answers, variable aliasing, duplicate
  suppression, ground success, tabled tail calls and caller cuts.
- Automatic GC disabled vs thresholds 1, 8, 64; forced collection between answers,
  independent consumer bindings, EQL identity for string/vector atoms and teardown.
- Left-recursive tabled DCG full parses and all prefix answers.
- Ground TNOT true/false/undefined, odd and even negative loops, removal of
  conditional answers with failed suffixes, late-answer invalidation, domination
  by unconditional variants, branch delay rollback and nonground generators
  with ground negative children.
- Independent alternating-fixed-point oracle: all 1,024 subsets of two-atom
  empty/single-literal rules (2,048 truth comparisons), plus 300 deterministically
  sampled three-atom programs (900 truth comparisons). These verify finite
  propositional cases, not unrestricted first-order completeness.
- 500-level dependency chain (501 tabled subgoals) completes under the same
  1 MiB Lisp control-stack limit.
- Rejection of floundering, untabled negation targets, cyclic table terms,
  host operations inside generators, host callbacks after conditional answers
  and database changes during active tabled queries.

This is a copying SLG implementation. Suspended consumers retain independent
WAM graphs; dynamic SCCs complete individually at local quiescence. SCC graph
traversals use explicit work lists. Shared frozen WAM stacks, subsumption,
immediate ground-success completion and incremental tables are outside this release. Existing heap statistics exclude table space
and suspended-worker allocation; no process memory or speed comparison with
XSB is claimed.

## Local scheduling and cut coverage

The same semantic suite and independent WFS oracle run after the scheduling change.
New cut cases run with automatic GC disabled and thresholds 1, 8, 64:

- Generator-entry cuts, pruning ordinary alternatives and retaining alternatives
  introduced after a cut.
- Completed child-table and recursive child-SCC cuts; other child answers remain
  available to subsequent goals in the same query.
- Helper-local cuts after an earlier caller suspension.
- Typed rejection of cuts over direct/mutual recursion, returned suspended helpers,
  frozen consumers in an earlier clause and delayed negative recursive calls.
- Completed undefined child SCC before a parent's cut.
- Tabled DCG predicate cuts and opaque PHRASE cuts, including after suspension.
- Two mutually recursive SCCs finish independently, with observed component
  count 2 and maximum completed-component size 2.
- Illegal cuts abort the cursor immediately, release partial tables and prevent
  continuing past the failed CALL/CUT.

This validates the implemented restriction; it is not a full SWI-Prolog/XSB
compatibility claim.

## Lisp-native builtins and cons terms

SBCL 2.2.9, Linux x86-64, 2 GiB dynamic-space ceiling, 1 MiB control stack:
**4,141 combined checks pass**. The core builtin registry contains **101 predicate
indicators**, plus seven aliases. ISO conformance and Prolog text conversion are
outside the specification.

`tests/builtins.lisp` covers arithmetic, cons graph operations, control/cut scopes,
meta-calls, exception rollback, dynamic updates, findall/bagof, atom/number
conversions and character/byte streams. Forced-GC checks use thresholds 1, 8 and
4096, as well as disabled collection. Stress cases retain 100,000 arithmetic tail
calls, 10,000 meta-calls and a 10,000-level arithmetic expression.

`tests/term-syntax.lisp` verifies native cons terms and dotted tails, cyclic inputs,
ordinary LIST/CONS data symbols, meta-calls, exceptions, dynamic definitions,
first-appearance BAGOF grouping, and all 27 removed predicate indicators.
Existing 100,000-element list, WAM instruction-family, DCG, SLG and independent
well-founded-model oracle tests remain in the combined suite.

Standalone append, DCG, SLG and builtin examples are checked locally.

## Quoted DCG syntax (0.8.1)

DCG regressions use quoted token lists and and/or/do controls, including variable
and compound tokens, empty productions, lexical callbacks, nested alternatives,
cut boundaries, tabled grammars and forced GC. Runtime grammar data is tested
separately from definition/query macros. Malformed and cyclic quoted token
sequences are rejected; legacy keyword syntax remains covered for compatibility.

## Interactive queries (0.9.0)

`tests/interactive.lisp` checks demand-driven alternatives (including infinite
REPEAT), EOF and explicit stop commands, invalid-command retries, ground success,
failure, cyclic answer printing, lexical callbacks, undefined SLG answers and
cursor teardown after stop, errors and nonlocal exits. Batch regressions use a
private collecting macro; the public `?-` interface is exercised separately.
