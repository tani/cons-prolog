# Predicate implementation layers

This refactoring was made against `main` at `3504d947`. The public inventory stays
at **101 predicate indicators**, plus the existing seven aliases. Implementation
is now separated into **62 public runtime primitives/adapters**, **8 compiler
forms**, and **31 derived predicates**. Five private adapter operations and three
private library helpers are excluded from the public inventory. This is a
boundary reduction, not a claim that 62 operations are a mathematically minimal
basis, nor a performance optimization or an ISO conformance claim.

## P1: protected shared library

`src/library/standard-library.lisp` contains ordinary clauses compiled by the same compiler
as user programs. `resolve-code` falls back to this shared base after looking in
the user database. Library predicates are not copied into each database and do
not appear in `current_predicate/1`, which continues to enumerate user definitions.
`clear-database` leaves the base library intact. Modification and clause-access
checks protect the entire public namespace, including aliases and private helpers.

The P1 definitions are `nonvar/1`, `number/1`, `callable/1`, `ground/1`,
`once/1`, `repeat/0`, `\+/1`, `\=/2`, and `\==/2`. There is no special repeat VM
instruction. Calls to derived aliases go through normal predicate resolution.

**Conditional retention:** `atomic/1` accepts all Common Lisp numbers, including
ratios and complex numbers, while `number/1` accepts integers and floats. Defining
it as atom-or-number would change the API. Using a host callback instead would
also lose support inside SLG generators, where callbacks are disallowed. It
therefore remains a small adapter until a broader numeric type primitive is justified.

`once` and negation containing lexical Lisp callbacks keep a source expansion:
callback objects are executable compiler input, not first-class Prolog terms.
Their ordinary term forms use library clauses. Source-time callable validation
is retained, including the original exception context. Cuts inside a called goal
remain opaque; cuts in conjunction/disjunction remain transparent to their clause.

## P2: thin adapters and ordinary wrappers

The following predicates now use library clauses:

| Family | Derived indicators |
| --- | --- |
| Default options | `open/3`, `close/1` |
| Current-stream I/O | `get_char/1`, `get_code/1`, `peek_char/1`, `peek_code/1`, `put_char/1`, `put_code/1`, `get_byte/1`, `peek_byte/1`, `put_byte/1` |
| Other defaults | `flush_output/0`, `at_end_of_stream/0`, `halt/0` |
| Newline | `nl/0`, `nl/1` |
| Atom relations | `atom_length/2`, `atom_chars/2`, `sub_atom/5` |
| Number relations | `number_chars/2` |

Character conversion uses `char_code/2` and a shared Prolog list relation. The
input/output direction is selected before traversing the list, preserving output
variables and open output tails. `sub_atom/5` uses two `atom_concat/3` calls and
length relations, preserving before-then-length enumeration order.

Private checks `%output_nonnegative/1`, `%chars_arguments/3`, and
`%sub_atom_arguments/5` retain validation order and errors for improper/cyclic
lists, partial inputs, negative offsets, and invalid characters. They perform no
relation enumeration. Removing these checks would silently turn some exceptions
into failure or permit modes the previous implementation rejected.

Explicit-stream I/O, EOF state, nonseekable lookahead, atom interning, numeric
parsing/printing, and arithmetic evaluation remain host adapters. Code/byte I/O
is retained separately to preserve EOF and stream-type validation.

An adapter wrapper marks its public error context. This context is saved/restored
with continuations, choice points, and exception snapshots, so private checks do
not expose helper names and later unrelated goals get their own contexts.

## P3: copies, updates, and collection

`copy_term/2` is the singleton result of `findall/3`; internal `iso-copy` remains
the iterative graph-copy operation for collected solutions, exceptions, and
other runtime work. Tests cover cycles, fresh variables, and repeated aliases.
This derived definition may allocate more than the previous direct adapter.

`retractall/1` ensures the dynamic predicate exists, then exhausts head deletions
with a failure-driven library loop. The private `%ensure_dynamic/1` preserves
observable empty predicate registration; `%retract_head/1` reuses the existing
snapshot deletion enumerator without exposing or inspecting clause bodies.
Head-only access is required because Lisp callback bodies cannot be represented
as ordinary Prolog terms. Bindings are rolled back while deletions persist.
Existing calls retain immutable clause/code snapshots.

`findall/3` and `bagof/3` retain the child-query collection boundary. For `bagof`,
free-variable handling, variant grouping (`iso-group-answers`), and result
construction (`iso-bagof-results`) are separate functions. Group keys are compared
with a variable bijection and their aliases aligned before collecting templates.
The grouping has not been replaced by ordinary equality or a superficial Prolog
list grouping operation.

## P4: source organization and kernel boundary

| Directory / module | Responsibility |
| --- | --- |
| `kernel/engine`, `kernel/wam`, `kernel/gc`, `kernel/slg` | Bindings, trail, choice points, execution, GC, tabling |
| `kernel/runtime` | Meta-call entry, continuation handling, exceptions |
| `syntax/compiler`, `syntax/wam-compiler` | Clause compilation and lowering |
| `syntax/control-syntax` | Conjunction/disjunction/if, lexical meta-form fallback |
| `syntax/let-syntax` | Lisp lexical cells and `let` expansion |
| `syntax/host-syntax`, `syntax/dcg` | Host callback construction and DCGs |
| `api/package`, `api/api`, `api/registry` | Public package/macros and predicate namespaces/inventory |
| `adapters/term-ops` | Graph inspection, copying, identity, checked unification |
| `adapters/arithmetic`, `adapters/adapter` | Numeric evaluation, type/atom/flag boundaries |
| `adapters/dynamic`, `adapters/collection`, `adapters/streams` | Database updates, answer collection, stream state |
| `adapters/builtins` | Runtime dispatch and primitive/syntax registration |
| `library/standard-library` | Protected ordinary Prolog clauses |

The irreducible execution boundary consists of binding/trail operations,
choice-point control and cut, runtime goal entry, exception snapshots, and table
scheduling. Graph inspection, host types, symbols, streams, flags, and database
updates are host/state boundaries. The implementation does not equate all of these
with special WAM instructions. `let` has no WAM primitive: it expands into the
existing Lisp bridge and lexical getter/setter closures.

`builtin-predicate-inventory` accepts `:kind :all` (default), `:primitive`,
`:syntax`, or `:derived`. The eight syntax indicators are `!/0`, `,/2`, `->/2`,
`;/2`, `=/2`, `true/0`, `fail/0`, and `false/0`; they remain available to meta-call
through runtime entry. Punctuation aliases keep their previous meanings.

## Validation

- SBCL 2.2.9: the complete suite passes **4,287 checks**, including the existing
  100,000-step tail-call and 10,000-token DCG checks, with a **1 MiB control stack**.
- New tests cover registry separation/protection, clearing databases, repeat,
  caller cut scope, failed partial unification, cyclic copies, character conversion
  modes, substring ordering, dynamic rules/callbacks, SLG, and context restoration.
- `tests/derived-observations.lisp` produces identical normalized observations
  against `3504d947` and this branch, including solutions, variable aliases,
  cyclic graph shape, error terms, answer order, EOF, and output effects.
- Other Lisp implementations have not been run in this environment. The existing
  multi-implementation Nix/CI configuration remains the verification mechanism.
- These finite checks are regression evidence, not a universal equivalence proof.

To reproduce the comparison, run the observation script once per checkout and
compare its stdout. Loading/compilation messages are suppressed by the script:

```sh
SPROLOG_ROOT=/path/to/reference sbcl --script tests/derived-observations.lisp > before.txt
SPROLOG_ROOT=/path/to/current sbcl --script tests/derived-observations.lisp > after.txt
diff -u before.txt after.txt
```
