# ISO compatibility observations

The goal is to execute external ISO tests to completion, identify implementation
defects, and document deliberate differences while retaining Lisp-native cons
graphs. This is not a separate ISO interpreter and does not claim full conformance.

## Source and scope

The first corpus is the definitions named `iso_*` in Logtalk's
[`tests/prolog`](https://github.com/LogtalkDotOrg/logtalk3/tree/bba0882757af2fc10bf5d3523ad84eb93c96dc30/tests/prolog),
pinned to commit `bba0882757af2fc10bf5d3523ad84eb93c96dc30`.
There are **782 test definitions**, including disabled definitions and alternative
conditional branches. This is not a count of distinct normative requirements.
Other prefixes, including `sics_*` and `lgt_*`, are outside this initial profile.
DCG, ISO modules, and the full ISO standard are not covered by this profile.

Logtalk updates its tests for the core standard and corrigenda and records their
origins in [NOTES.md](https://github.com/LogtalkDotOrg/logtalk3/blob/bba0882757af2fc10bf5d3523ad84eb93c96dc30/tests/prolog/NOTES.md).
Its source files are Apache-2.0, copyright Paulo Moura and contributors.
The original tests are fetched separately, not copied into sprolog.
`tests/iso/upstream.json` pins the hashes of all 192 input files and the case count;
a changed, missing, or extra file is a fatal import error.

The [Ciao ISO suite](https://github.com/ciao-lang/iso_tests) was also investigated.
It uses Ciao test assertions, pre/postconditions and helper libraries. Integrating
that framework is separate work; its advertised 1,047 cases are not included in
the denominator or sprolog's results.

## Running

Requirements: Python 3, SBCL, and SWI-Prolog 9.x. SWI parses the Logtalk test DSL
only; SBCL and sprolog execute the test goals.

```sh
git clone https://github.com/LogtalkDotOrg/logtalk3 /tmp/logtalk3
git -C /tmp/logtalk3 checkout bba0882757af2fc10bf5d3523ad84eb93c96dc30
python3 -m unittest discover -s tests/iso -p 'test_*.py'
python3 tests/iso/run.py --upstream /tmp/logtalk3 \
  --baseline tests/iso/baseline.json --output iso-results --jobs 2
```

`--sbcl` and `--swipl` accept executable paths. The runner unit tests use
`ISO_SBCL` and `ISO_SWIPL` for nonstandard installations.
`--filter functor_3` selects a subset without changing the complete inventory.
`--timeout` sets each process's wall-clock limit (default five seconds).
Each test gets a fresh database, working directory and SBCL process with a 1 MiB
control stack. A timeout, missing protocol result or process failure is a FAIL;
remaining cases still run. A library-build or importer failure aborts the command.
Workers select `read_syntax=prolog` and `write_syntax=prolog`; native cons terms
are unchanged. Ordinary library use defaults both flags to `lisp`.

The outputs are `cases.jsonl` (generated program, goal, unchanged expectation and
source location), `report.json` (all observations and source hashes), and
`report.md`. No cases are silently omitted from the selected inventory.

| Result | Meaning |
|---|---|
| PASS | The adapted framework checked the upstream expectation successfully |
| XFAIL | A case-specific documented difference produced its exact recorded observation |
| FAIL | The case executed but failed its expectation, timed out, or crashed |
| BLOCKED | A required fixture, condition, assertion mode, source load or query parse is not supported yet |

An expected difference that starts passing, changes its failure, or becomes blocked
is reported as FAIL with `expectation_changed`. Missing or stale expectation IDs
are fatal errors. There are no family-wide exclusions or changed upstream expected
answers. Postcondition failures include the resulting terms, not just a boolean.

The baseline gate detects regressions and changes to existing failures/blockers;
improvements to PASS are allowed. **A successful baseline CI job does not mean
that all ISO tests pass.** Use `--strict` to return failure whenever any FAIL or
BLOCKED remains. Baseline changes require inspecting the actual observations,
not replacing them with XFAIL.

## Framework adaptation

The importer reads the upstream sources without executing the Logtalk compiler.
It unwraps `{Goal}` only in goal positions and retains braces in data. It translates
supported lgtunit input/suppression fixtures and expectations, and copies the
file's ordinary helper clauses and predicate/operator declarations into a fresh
database. Logtalk's list-form declarations are expanded into individual declarations.
Helpers such as FORALL and variant/approximate assertions are supplied by the
test driver; they are not additions to sprolog's public predicate inventory.
Approximate assertions retain lgtunit's fallback epsilon of 1e-12 and relative
tolerance of 1e-5. Source parsing uses SWI's ISO mode to preserve ISO continuation
whitespace rather than SWI's default whitespace-skipping extension.

Conditional compilation, disabled tests, unimplemented per-case options, unsupported
fixture/object dispatch, and deterministic-choicepoint assertions are explicit
BLOCKED entries. This adapter is not a Logtalk backend. Its own tests exercise
false results, wrong exception/ball patterns, variable aliasing, failed assertions,
existential expectations, quoted delimiters, timeouts and continued execution.

The upstream RETRACT tests 04 and 05 depend on deletions performed by earlier
tests. `fixtures.json` declares those exact predecessor IDs. Each worker replays
them in dependency order in its own fresh database and verifies their original
expectations before running its target. A predecessor failure is BLOCKED at
SETUP. Dependencies are recorded in `cases.jsonl` and validated for missing,
blocked, cross-source and cyclic references. This preserves per-case isolation
without changing upstream expectations or relying on parallel execution order.

## Deliberate differences and remaining work

Only confirmed, case-specific consequences of the term model are currently
listed in `expected-differences.json`:

- Empty-list atom conversion uses the name `nil` rather than `[]`.
- A native list's CAR is its application name; list cells are not ISO `'.'/2` terms.
- KEYSORT uses native dotted pairs, rather than `Key-Value` compound terms.
- NIL's operator name is `nil`, distinct from the protected atom name `[]`.

Term ordering, control, arithmetic, validation errors and missing flags are not
automatically exempted as term-model differences.
The two remaining FAIL entries are `iso_sort_2_02` and
`iso_term_comparison_08`: the existing native total order differs from ISO
numeric/compound ordering. They remain FAIL pending an explicit ordering policy.
The 115 BLOCKED entries still require framework conditions, fixtures or assertion
modes; they are not passing tests. Output-assertion fixtures remain BLOCKED even
though a Prolog writer is now available; output behavior has separate native tests.
See `baseline.json` and the generated report for individual cases.

The textual reader now accepts binary/octal/hexadecimal integers, character-code
literals, ISO control/hex/octal escapes, and quoted delimiter atoms. These fixes
preserve the existing term model and default S-expression I/O interface.
It also distinguishes prefix-operator layout from functional notation and accepts
bare semicolon atoms in argument positions.

## Measurements

SBCL 2.2.9, 1 MiB control stack, SWI 9.2.9 as the source importer:

| Result | Initial baseline | After failure fixes |
|---|---:|---:|
| PASS | 579 | 656 |
| XFAIL | 4 | 9 |
| FAIL | 84 | 2 |
| BLOCKED | 115 | 115 |
| Total | 782 | 782 |

Of the original 84 failures, 77 now pass, five are confirmed term-model
differences with exact observations, and two ordering failures remain.
Fixes cover runtime control dereferencing/cut scope, variable clause bodies,
zero-arity reflection/retraction, protected-procedure errors, powers, ARG errors,
operator validation, `max_arity`, and Prolog stream reading. Two RETRACT failures
were framework setup defects corrected by predecessor replay.

With the independent Lisp/Prolog syntax flags and Prolog writer added, the
complete native test suite passes **5,086 checks**; the driver passes nine
tests, including a 23-case framework fixture and a timeout/continuation check.
The 54 existing serialized derived observations are unchanged from the initial
baseline revision and remain unchanged by the I/O flag/writer additions.
These are separate measurements. An ISO coverage percentage is not reported.
