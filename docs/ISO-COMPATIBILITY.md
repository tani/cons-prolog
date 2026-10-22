# ISO compatibility observations

The active corpus is J. P. E. Hodgson's two plain-Prolog validation suites:
[source descriptions](https://www.deransart.fr/prolog/suites.html).
They replace the former Logtalk importer and baseline. Running these checks
requires Python 3 and SBCL; no Logtalk, Ciao or SWI-Prolog is required.
This measures finite observations while preserving native cons terms, not an
ISO conformance certificate or a percentage of the standard.

## Sources and inventory

| Distribution | Scope used here | Check points |
|---|---|---:|
| [INRIA suite](https://www.deransart.fr/prolog/inriasuite.tar.gz) | Every record in the original driver's active `file/1` inventory | 420 |
| [Standard-example suite](https://www.deransart.fr/prolog/prologsuite.tar.gz) | Every `test_true/1`, `test_false/1`, `test_val/3` and `error_test/2` call in `sec*.pl` | 567 |
| Total | Includes overlaps between the two suites | 987 |

These are 1999 distributions, not an exhaustive executable specification with
all later corrigenda. INRIA's README describes its driver as vanilla ISO Prolog
and excludes I/O testing; the standard-example suite supplies I/O/directive checks.
INRIA's inactive auxiliary/experimental files are outside its original active
inventory. Its documented non-runnable HALT data file is inactive; the example
suite's HALT/1 assertion runs in its own process and verifies exit status 7.

`tests/iso/upstream.json` pins both complete archive SHA-256 digests, every
extracted file digest and the 987-case count. Changed, extra or missing files
abort the run. Originals are downloaded separately and are not vendored.
Their authorship/notices remain with Hodgson and the original contributors.
The standard-example sources permit use with acknowledgment. This adapter
acknowledges J. P. E. Hodgson, Saint Joseph's University, and Deransart,
Ed-Dbali and Cervoni's formal-specification work.

## Running

```sh
python3 tests/iso/fetch.py --output /tmp/upstream-hodgson
python3 -m unittest discover -s tests/iso -p 'test_*.py' -v
python3 tests/iso/run.py --upstream /tmp/upstream-hodgson \
  --baseline tests/iso/baseline.json --output iso-results --jobs 2
```

Both stream syntax flags are `prolog` inside workers; ordinary library use
defaults to `lisp`. `--sbcl` accepts an executable path; unit tests use
`ISO_SBCL`. `--filter inria/arg` selects checks without changing the complete
inventory. `--timeout` sets each worker's wall-clock limit (default five seconds).
Each target gets a fresh SBCL process with a 1 MiB control stack, database,
working directory and copy of the original fixtures. Timeouts/crashes do not
stop subsequent targets. Source validation or inventory/compiler failure aborts.

The native reader creates `cases.json` and generated native term files in
`programs/`. IDs identify the INRIA file/record ordinal or example file/top-level
term/check ordinal; `line` identifies the containing source term.
`report.json` and `report.md` retain every result. JSON includes complete source
hashes, adaptation notes, timings and process diagnostics.

## Result meanings

| Result | Meaning |
|---|---|
| PASS | An executed target satisfied its recorded expectation |
| FAIL | A target differed, timed out, crashed, produced no result, or was not reached |
| XFAIL | A case-specific native term-model difference matched its exact recorded failure |
| SKIP | An explicit applicability premise is false |
| BLOCKED | Loading or setup failed before the target could start |

PASS is a complete protocol result, not text found in test output. HALT requires
its target-start marker and actual exit code. A changed or newly passing XFAIL
becomes FAIL for review; stale expectation IDs are fatal. The baseline rejects
changed nonpassing observations/regressions and allows ordinary improvements
to PASS. **Green baseline CI does not mean all tests pass.** `--strict` fails
if FAIL or BLOCKED remains.

The ten current SKIPs are individually explained in `adaptations.json`:
two finite-max-arity cases, five bounded-integer overflow assertions, and three
cases assuming character codes 1000 or 9999 are unavailable. Their premises are
false for unbounded arity/integers and the supported Unicode scalar values.

## Port boundary and setup

`tests/iso/adaptations.json` records compatibility changes and limitations.
The original goals and expected answers are retained.

INRIA's driver still computes/compares substitutions. Private ordinary Prolog
definitions supply its assumed APPEND, MEMBER and LENGTH helpers. Two harness-only
UNIV guards and the formal-error comparison boundary are adapted because native
lists do not have ISO `'.'/2` functors. Calls under test to FUNCTOR, ARG or UNIV
are not intercepted or replaced.

INRIA records are read at execution time after replaying preceding goals in that
file. This preserves reader flags/database effects within each isolated target.
It matters for `double_quotes`: a preceding record changes how the next quoted
input is read. `executed_goal` records the runtime-read target; the inventory's
initial parse can differ for those cases.

Each example assertion is tagged and its containing zero-arity predicate runs
with the source's setup. Section 8.9 retains the `test_89` database-update
sequence; omitted verification helpers receive their ASSERTA/ASSERTZ setup
explicitly. INCLUDE/ENSURE_LOADED resolve relative to copied fixtures, and
initialization runs after loading. A private AND/2 helper is alpha-renamed to
avoid the protected native alias. GO7_4 is bridged to GO_74 to repair the upstream
initialization spelling.

The four small checking helpers retain copied goals, first-solution behavior,
unifying value expectations and formal exception matching. Exceptions in a
false-expectation check are failures. Logging is separate from the protocol and
tested streams. Prose such as “Should now write” remains manual documentation:
its accompanying explicit success/failure/exception check is automated, but the
prose is not counted as another output assertion.

The native reader handles repeated right-associative operators, including long
conjunctions, iteratively. This permits the long arithmetic test clauses without
raising the 64-frame limit on genuinely nested syntax.

## Observed baseline

SBCL 2.2.9, 1 MiB control stack:

| Suite | PASS | XFAIL | FAIL | SKIP | BLOCKED |
|---|---:|---:|---:|---:|---:|
| INRIA | 398 | 3 | 15 | 4 | 0 |
| Standard examples | 528 | 3 | 30 | 6 | 0 |
| Total | 926 | 6 | 45 | 10 | 0 |

Thus 977 checks execute and ten have false applicability premises.
The six XFAILs are empty-list atom spelling `nil` versus `[]` and the native
application/list-cell FUNCTOR interpretation, exercised in both suites.
Term ordering and error validation are not exempted automatically.

The 45 FAILs remain visible. They mix implementation differences with historical
expectations/source issues, including exact rounded floating-point values,
old error classes/culprits, and SUB_ATOM expectation tables. No tolerance or
replacement answer is silently introduced; inspect the report before treating
a particular failure as an implementation defect.

The native regression suite passes **5,089 checks**. Ten adapter tests exercise
a 28-check synthetic fixture, wrong/missing exceptions, aliasing, setup/order,
reader-flag replay, process/file/database isolation, real HALT status,
spoofed output, timeout continuation and source inventories. The 54 existing
derived observations remain byte-for-byte unchanged.

The former Logtalk corpus included conditional and disabled definitions.
Its 782-definition counts are not comparable to this 987-check baseline.
Its importer, dependency, fixtures and baseline have been replaced.
