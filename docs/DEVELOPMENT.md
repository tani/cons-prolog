# Development

## ASDF

`sprolog.asd` defines a `package-inferred-system`. Loading `sprolog` loads
`sprolog/src/builtins` and its inferred prerequisites; testing it loads
`sprolog/tests`, which calls the existing `run-tests` entry point.
There is no hand-maintained component list.

The public package has canonical name `sprolog/src/package` and nickname
`sprolog`. Each source file declares a `sprolog/src/<file>` dependency package,
then evaluates its implementation in `sprolog`. These dependency packages
are intentionally empty: the WAM modules share structures, internal symbols,
and mutually recursive functions. This preserves their identities without
exporting all implementation details or moving the public API.

Tests use the same arrangement: `sprolog/tests/tests` has nickname
`sprolog/tests`, and each subsequent test module declares its prerequisites.
`register-system-packages` maps public nicknames and `sprolog/atoms` to their
defining systems. When adding a module, give its dependency package the
system's path name and add its prerequisites to `:use` or `:import-from`.

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
in ECL/MKCL. The term-instruction dispatch resolves its function cell explicitly
so instrumentation still works after those implementations warm their call cache.

The allocation/profiling scripts under `benchmarks/` remain SBCL-specific.
The ordinary library and semantic tests do not require SBCL internals.
For SBCL's explicit small-stack regression, run:

```sh
sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
```
