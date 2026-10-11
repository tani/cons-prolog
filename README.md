# sprolog

S-expression Prolog for SBCL, with native Lisp cons terms, an explicit WAM execution model, DCGs, SLG variant tabling and VM garbage collection.

An independent implementation inspired by the PAIP / Allegro Prolog APIs. ISO Prolog conformance and full Allegro compatibility are outside its scope. [MIT licensed](LICENSE).

## Load

No external Lisp libraries are required. From the repository directory:

```lisp
(require :asdf)
(asdf:load-asd (truename "sprolog.asd"))
(asdf:load-system "sprolog")
(use-package :sprolog)
```

## Define and query

```lisp
(<-- (append () ?ys ?ys))
(<- (append (?x . ?xs) ?ys (?x . ?zs))
    (append ?xs ?ys ?zs))

(?- (append ?xs ?ys (a b c)))
;; => (((?xs) (?ys a b c))
;;     ((?xs a) (?ys b c))
;;     ((?xs a b) (?ys c))
;;     ((?xs a b c) (?ys)))
```

`<--` replaces clauses of the same name and arity; `<-` appends a clause. `?x` is a logic variable; each `?` is anonymous. `?-` returns all solutions as a list of binding alists. Failure is `NIL`; one solution without bindings is `(NIL)`.

Terms and lists share the same Lisp cons representation. Write `(f a b)` or `(a . ?tail)` directly. Definition and query macros treat goals as data, so ordinary terms need no quote.

## DCGs

```lisp
(---> (article) '(the))
(---> (noun cat) '(cat))
(--> (noun dog) '(dog))
(---> (sentence ?noun)
  (article)
  (noun ?noun))

(?- (phrase (sentence ?noun) (the cat)))
;; => (((?noun . cat)))
```

`--->` replaces grammar clauses; `-->` appends one. Within a DCG, `'(a b)` denotes a token sequence; variables inside it still unify. Use `and` for sequences, `or` for alternatives and `do` for ordinary goals that consume no input.

## Tabling

```lisp
(table 'path 2)
(<-- (path ?x ?y) (path ?x ?z) (edge ?z ?y))
(<- (path ?x ?y) (edge ?x ?y))
(<-- (edge a b))
(<- (edge b c))
(<- (edge c a))

(?- (path a ?y))
;; => (((?y . b)) ((?y . c)) ((?y . a)))
```

SLG supports left and mutual recursion, plus ground `tnot`. Cuts over unfinished tables raise an error. See the [user guide](MANUAL.md#slg-resolution) for details and restrictions.

Use `prolog` / `lisp` / `lispp` for lexical Lisp callbacks and `make-query` / `next-solution` / `close-query` for streaming answers. Builtins cover unification, arithmetic, dynamic definitions, exceptions, answer collection and character/byte I/O.

## Examples and tests

```sh
sbcl --script examples/append.lisp
sbcl --script examples/dcg.lisp
sbcl --script examples/slg.lisp
sbcl --script examples/builtins.lisp
sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
```

Validated on SBCL 2.2.9 / Linux x86-64: 4,115 checks pass, including one million tail calls with a 1 MiB Lisp control stack.

## Documentation

- [User guide](MANUAL.md): terms, queries, Lisp callbacks, DCGs, SLG, WAM, GC and limitations
- [Builtins](BUILTINS.md): supported predicates and Lisp-friendly names
- [Validation](VALIDATION.md): semantic coverage and stress tests
- [Roadmap](ROADMAP.md) and [changelog](CHANGELOG.md)
