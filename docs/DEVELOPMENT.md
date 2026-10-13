# Development

## ASDF

`sprolog.asd` defines a `package-inferred-system`. Loading `sprolog` loads
`sprolog/src/api/package`, the final public facade, and its inferred prerequisites.
Testing loads `sprolog/tests/suite`, whose `run-tests` entry point runs the suite.
There is no hand-maintained ASDF component list.

Each source file uses `uiop:define-package` and enters that same package with
`in-package`. Definitions belong to their implementation module. Cross-module
calls use explicit `:import-from`, and modules export the interfaces used by their
consumers. Only the final public facade has the `sprolog` nickname. It uses
`:use-reexport` to aggregate `api/public`, whose explicit imports and
exports select the public API. Internal interfaces are not reexported through it.
Tests follow the same arrangement, with shared test helpers and a final runner.
The test runner alone has the `sprolog/tests` nickname.

The execution pipeline contains runtime/compiler/adapter cycles. Three explicit
boundaries make its ASDF load graph acyclic:

- `kernel/model` owns record types and conditions. Modules import the constructors
  and accessors they actually use; algorithms remain in their provider modules.
- `kernel/instructions` owns shared WAM instruction and source-marker identities.
- `kernel/protocol` declares late execution hooks. Providers register their own
  function symbols after loading, and hooks resolve the current function cell.
  This avoids importing an implementation that depends on the consumer, while
  retaining runtime replacement and instrumentation. Hook calls add dispatch
  overhead; the package refactoring is not claimed to improve performance.

`api/state` owns the predicate registries and adapter configuration. Predicate
library storage is still shared intentionally; implementation function namespaces
are separate. Initialization dependencies remain explicit where a provider must
be installed before a consumer can compile callbacks or library clauses.

`register-system-packages` maps the public facade and runner nicknames, and the
atom package, to their defining systems. When adding a module, its package name
must match its ASDF path and its `in-package` form.

```lisp
(require :asdf)
(asdf:load-asd (truename "sprolog.asd"))
(asdf:load-system "sprolog")
(asdf:test-system "sprolog")
```

ASDF 3.1 or later is required. No Quicklisp dependencies are needed.

## Nix outputs

The flake uses the same pinned Nixpkgs and flake-parts inputs as
`tani/nix-common-lisp`. It supports SBCL, ECL, ABCL, CCL, MKCL, CLISP, CMUCL,
and Clasp where the package is available and not marked broken.

For each implementation `<impl>` it exports:

| Output | Purpose |
| --- | --- |
| `packages.lib-<impl>` | Compiled ASDF library and test systems |
| `packages.main-<impl>`, `apps.main-<impl>` | REPL with the public API loaded |
| `packages.test-<impl>`, `apps.test-<impl>` | Complete suite; nonzero exit on failure |
| `checks.test-<impl>` | Sandboxed library build and test run |
| `devShells.<impl>` | Development shell with that implementation |

`packages.default` is the SBCL library. `devShells.default` includes all
available implementations. The default overlay adds `sprolog` to each Lisp's
package set and exports `sprolog-<impl>` REPL wrappers.

Unlike the template's Fibonacci demo, this library does not define an
application entry point or dump an executable image. `main-*` starts the Lisp
REPL, and `lib-*` can be consumed through `lisp.withPackages`.

CI discovers check names directly from the flake on each target platform,
then builds each check independently. The entire semantic and stress suite
runs on each implementation, including one million tail calls and deep terms.

## Portability

The default halt hook uses `uiop:quit`. Globally special Lisp variables are
rejected by the `let` bridge: SBCL uses its declaration introspection, and
other implementations use an ANSI CL compiled binding probe.

Worklist loops test for termination before popping their next item, avoiding
implementation differences in `LOOP` clause ordering. Guarded VM execution is
bound to a variable before testing it, preventing duplicate native evaluation
in ECL/MKCL. The term-instruction dispatch and interactive cursor construction resolve their
function cells explicitly so instrumentation still works after those implementations
warm their call cache. Circular interactive answers use ordinary circle-aware
printing to avoid a CCL pretty-printer hang.

The allocation/profiling scripts under `benchmarks/` remain SBCL-specific.
The ordinary library and semantic tests do not require SBCL internals.
For SBCL's explicit small-stack regression, run:

```sh
sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
```

## Source layers

| Directory | Responsibility |
| --- | --- |
| `src/api/` | Public interface selection/facade, Lisp query/definition API, predicate registry |
| `src/kernel/` | Execution machine, WAM instructions, GC, SLG, meta-call and exceptions |
| `src/syntax/` | Clause compiler, lowering, DCG and lexical/control source expansion |
| `src/adapters/` | Term graphs, host types, arithmetic, dynamic database, solution collection, streams, dispatch |
| `src/library/` | Derived predicates compiled from ordinary Prolog clauses |

Directory boundaries describe responsibility. Every implementation file now has
its own package and inferred subsystem; loading the complete `sprolog` system
installs the execution providers and derived library before exposing the facade.
