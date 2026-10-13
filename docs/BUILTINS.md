# Lisp-native terms and builtins (0.9.1)

[README](../README.md) · [User guide](MANUAL.md)

sprolog uses Lisp cons graphs as its term model. There is no separate Prolog
compound type and no ISO conformance claim. `(f a b)` is exactly the same cons
structure whether used as data or as a predicate application. Goal position gives
it a callable interpretation. Data terms can have variable heads, improper tails,
sharing and cycles. `(f)` is a one-element list in data position and an `f/0` call
in goal position. `()` is NIL. `?x` is a logic variable; each `?` is fresh.

```lisp
(<-- (append () ?ys ?ys))
(<- (append (?x . ?xs) ?ys (?x . ?zs)) (append ?xs ?ys ?zs))
(query '((append ?xs ?ys (a b c))))
(query '((= ?term (f a (g b)))))
(query '((= ?tail (a . ?tail)) (ground ?tail)))
```

`list`, `cons`, and `:compound` have no special term-constructor meaning.
`(list a b)` is data containing the symbol LIST, followed by A and B; `(cons a b)`
is data containing CONS, A and B. Native lists/dotted pairs are used directly.
Answers and Lisp callbacks use the same cons representation as input terms,
with unbound variables exported as fresh symbols. Lisp bridge expressions keep
normal Common Lisp evaluation rules; source goals and their data are quoted by
the query/definition macros.

## Supported builtins

The registry exposes 101 public predicate indicators, plus seven aliases.
`src/adapters/builtins.lisp` registers primitive adapters and syntax;
`src/library/standard-library.lisp` installs the derived predicates.
`(sprolog:builtin-predicate-inventory)` lists the core indicators by name/arity;
aliases are listed below. This inventory excludes user predicates and separate
DCG/SLG APIs such as PHRASE and TNOT.

| Family | Operations |
|---|---|
| Control | true/fail, cut, call/1..8, and/or, if-then, negation, once/repeat, catch/throw |
| Unification | `=`, `/=`, occurs check, subsumption |
| Cons term inspection | var/nonvar, atom/atomic, number/integer/float, compound/callable, ground/acyclic_term, term_variables, copy_term, `==`/`/==` |
| Arithmetic | is, arithmetic comparisons, integer/floating functions, logand/logior/lognot |
| Dynamic definitions | asserta/assertz, retract/retractall, abolish, clause, current_predicate |
| Collection | findall, bagof |
| Streams | open/close, current/set input/output, flush, stream properties/positions, end-of-stream |
| Characters and bytes | get/peek/put char/code/byte, nl |
| Atoms and numbers | atom_length/concat, sub_atom, atom_chars/codes, char_code, number_chars/codes |
| Environment | current/set flags, halt |

`compound/1` means a nonempty cons term. `callable/1` retains the broad symbol/cons
classification; actual calls additionally require a finite application with a
symbol in predicate position. `atom/1` tests symbol atoms, rather than Common
Lisp's broader ATOM predicate. Ordinary Lisp symbols retain package identity.
NIL has the atom name `nil`, not a translated Prolog empty-list spelling.
Atom/number conversion helpers use a private generated-atom namespace and bridge
those generated atoms by printed name; this is independent of any source parser.

| Preferred spelling | Retained punctuation alias |
|---|---|
| `/=` | `\=` |
| `/==` | `\==` |
| `===` | `=:=` |
| `=/=` | `=\=` |
| `/+` | `\+` |
| `and/2` | `,/2` |
| `or/2` | `;/2` |

`=/2` unifies cons graphs. `/=/2` tests immediate nonunifiability without binding
variables. `==/2` and `/==/2` test structural identity while preserving variable
identity, not host EQ identity of cons cells. `===/2` and `=/=/2` evaluate arithmetic
expressions. Bitwise expressions use `logand`, `logior`, `lognot`; their punctuation
spellings remain supported. Integers are unbounded; computed floating results use
SBCL double precision. ROUND retains ties away from zero.

`->/2` commits to the first condition solution. `(or (-> condition then) else)`
selects ELSE only if CONDITION fails, not if THEN fails. AND/OR are cut-transparent;
CALL and negation have opaque cut boundaries. DCG definitions use `-->` for append
and `--->` for replacement.

Assertions publish immutable clause/code snapshots; active calls retain their
entry definitions. Builtins cannot be overwritten. `(rule head body)` is accepted
by assertion/retraction operations; elsewhere RULE is an ordinary data symbol.
BAGOF groups variant free-variable bindings in first-appearance order and retains
answer order inside each group; no standard term ordering is imposed. FINDALL
keeps every answer in execution order.

## Deliberately removed operations

The following 11 term-model/ordering predicates are removed:

- `functor/3`, `arg/3`, `=../2`.
- `@</2`, `@=</2`, `@>/2`, `@>=/2`, `compare/3`.
- `sort/2`, `keysort/2`, `setof/3`.

Prolog text translation and output are also removed:

- `read/1,2`, `read_term/2,3`.
- `write/1,2`, `writeq/1,2`, `write_canonical/1,2`, `write_term/2,3`.
- `op/3`, `current_op/3`, `char_conversion/2`, `current_char_conversion/2`.
- Lisp APIs `iso-read-term`, `iso-write-term`, `iso-predicate-inventory`.
- Operator tables and lexer-only flags `char_conversion`, `double_quotes`, `max_arity`.

There is no `.pl` loader, Prolog parser/printer, or automatic conversion to Prolog
terms. Use Common Lisp I/O through the Lisp bridge when S-expression I/O is needed.
Character/byte stream operations remain supported. Removed predicate names follow
the normal unknown-predicate behavior and may be defined as user predicates.

## Runtime and embedding

WAM, managed VM GC, DCG, SLG and its well-founded negative resolution remain.
Cons graphs are shared by ordinary and tabled execution. Rational-tree unification
is the default; occurs-check unification is available explicitly.

Open streams persist until explicitly closed. Stream options include type,
reposition, alias and eof_action; close supports force. Bindings and exception
handlers survive VM GC and rollback. The existing Lisp exception API
`iso-exception`/`iso-exception-term` and embedding hook `*iso-halt-function*` retain
their historical names; exception payloads are plain S-expressions. HALT exits SBCL
by default. Unknown predicates raise an existence error by default; the unknown
flag can select failure instead. These conventions are sprolog's own specification.

## Source LET control

`(let name expression)` binds a nonspecial Lisp variable for later host bridge
expressions. It is compiled by source macros and is not a core predicate
indicator. See [the user guide](MANUAL.md#lexical-let) for scope, declarations,
backtracking and embedding restrictions. Allegro-style dynamic `let*` is not
implemented.

## Implementation layers

The public inventory is unchanged. 31 indicators now run as ordinary protected
Prolog clauses; see [implementation layers](PRIMITIVES.md) for the classification,
private adapter boundary, source organization, and validation results.
