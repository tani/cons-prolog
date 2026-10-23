# Bundled ISO Prolog validation

The repository contains an Apache-2.0 port of Logtalk's ISO examples: **782 test
definitions from 93 source files**, including disabled tests and alternate
conditional branches. Normal execution is offline and requires only Python 3 and
SBCL. Neither Logtalk nor SWI-Prolog is loaded by the runner.

This is a finite validation corpus, not a complete executable specification or an
ISO conformance certificate. It preserves sprolog's native cons term model.

## License and provenance

`tests/iso/vendor/logtalk/` contains unmodified test sources, their provenance
notes, and the upstream LICENSE and NOTICE. The pinned upstream revision is
`e0f2576eef32aa5d5732a0d47531d0f62b9a31f1` of
[LogtalkDotOrg/logtalk3](https://github.com/LogtalkDotOrg/logtalk3).
The selected source files carry Apache-2.0 SPDX notices. Upstream's
`tests/prolog/NOTES.md` records contributions and reuse permissions.

`tests/iso/suite/` contains the checked-in plain Prolog port, its Apache-2.0
LICENSE/NOTICE, and `cases.json`. Original notices are retained and modifications
are identified. Ported cases are not relicensed as MIT. The independent
`harness.pl`, Python driver, worker and development converter use the project's
MIT license.

`upstream.json` records SHA-256 digests for every original and ported file.
Missing, changed, extra or symlinked files abort validation. Each case records
its original source, line, name, standard reference, upstream expectation,
strict expectation, options, conditions and any individual adaptation.

The Hodgson INRIA/standard-example archives and their downloader are no longer
used. No license-unclear Hodgson corpus is bundled. Earlier observations remain
historical records in `docs/VALIDATION.md` and git history.

## Running

```sh
python3 -m unittest discover -s tests/iso -p 'test_*.py' -v
python3 tests/iso/run.py --baseline tests/iso/baseline.json --jobs 2
python3 tests/iso/run.py --filter predicates/read_term_3 --strict
```

`--sbcl` accepts an executable path; unit tests use `ISO_SBCL`. Each applicable
case gets a fresh SBCL process with a 1 MiB control stack, database and temporary
working directory. Both stream syntax flags are `prolog`; ordinary library use
still defaults to `lisp`. Five-second per-case timeouts, crashes, loading/setup
errors and missing/malformed protocol results are FAIL. They never count as
successful tests. The runner continues after a timeout.

`iso-results/report.json` retains every result, source hashes, expectations,
timings and diagnostics. The baseline rejects missing IDs and changed nonpassing
observations while allowing improvements to PASS. An exact, individually
explained native-model failure can be XFAIL; stale or unexpectedly passing
XFAILs require review. **A green baseline job does not mean ISO conformance.**
`--strict` returns nonzero while any FAIL remains.

## Port and applicability

All `iso_` definitions in the selected upstream revision are accounted for.
The other upstream prefixes (`lgt_`, `sics_`, `eddbali_`, `wg17_`, etc.) are not
part of this inventory; copied helper predicates are retained where needed.
The names alone do not establish that an example prescribes defined ISO behavior.

- Logtalk object declarations are removed. Goal-position `{Goal}` wrappers and
  fixture messages are lowered; braces inside data, lists and variable sharing
  are preserved. The checked-in `.pl` files need no import at execution time.
- Input/output fixtures are ordinary Prolog clauses using files and streams.
  Contents, bytes and unread tails are actually checked. Test output is separate
  from the result protocol. `clean_file/1` leaves deletion to the parent process's
  temporary-directory cleanup, since file deletion is not an ISO core predicate.
- `true`, `false`, postconditions, existential success, thrown balls, exact formal
  errors, variants and subsumption have separate checks. False expectations do
  not accept exceptions. Cleanup errors also fail the case.
- The `retract/1` examples that consume earlier clauses explicitly replay their
  recorded predecessors within the isolated worker.
- Logtalk's permissive alternative error patterns are narrowed to their reviewed
  standard first alternative. Both versions remain visible in `cases.json`.
- `iso_setof_3_17` is corrected to test both allowed relative variable orders
  inside the success branch. Upstream placed one order in an unreachable else
  branch after successful SETOF. The original source remains unchanged.
- STO/cyclic-term examples are SKIP, including their nominally enabled branches:
  undefined ISO behavior does not impose new requirements on native extensions.
  Other upstream-disabled cases and false runtime applicability conditions are
  also SKIP, with the reason retained. They are not counted as passes.
- The one `deterministic` expectation checks exactly one answer. A portable ISO
  driver cannot inspect residual choice points; this is explicitly a weaker
  observation. Approximation is confined to explicit upstream `=~=` checks;
  other numerical equalities remain exact.

## Specification policy and observations

Defined ISO requirements take precedence. Implementation-defined,
implementation-dependent and undefined behavior are distinguished; existing
extensions are retained where compatible with defined ISO requirements.

The current SBCL observation is **707 PASS, 8 XFAIL, 5 FAIL, 62 SKIP, 0 BLOCKED**.
The 62 skips comprise 45 STO definitions, six other disabled definitions, and
11 false applicability/alternate-branch conditions. Counts include both source
branches and must not be presented as 782 independent executed obligations.

The eight XFAILs retain native NIL spelling (two), list-cell FUNCTOR (one),
native-pair KEYSORT (one), canonical list output (one), and explicit `'.'/2`
versus native-list syntax (three).

Five failures remain visible for analysis; they are not suppressed by the port:

| Cases | Observation requiring review |
|---|---|
| `iso_op_3_10` (active branch) | Expected operator permission error was not raised |
| `iso_op_3_11`, `iso_op_3_12` | Defining an operator named `[]` did not raise the expected permission error |
| `iso_put_byte_2_04` | Reports `type_error(integer,ty)` where the example expects `type_error(byte,ty)` |
| `iso_read_term_3_05` | Syntax-error recovery consumed a leading space expected by the unread-tail assertion |

These are observed differences, not a claim that every remaining example is an
unambiguous processor defect. In particular, error recovery and implementation
extensions need review against the normative text before changing behavior.

## Regeneration

Normal runs use only committed files. Optional development regeneration uses
SWI-Prolog as a reader/serializer for Logtalk syntax, not as a test oracle:

```sh
python3 tests/iso/regenerate.py
# or: python3 tests/iso/regenerate.py --swipl /path/to/swipl
```

This reads the bundled originals without network access, refuses changed source
pins, rebuilds the plain Prolog files and metadata, and refreshes port hashes.
Review converter changes and regenerated diffs together. Updating the upstream
revision or license notices requires an explicit source-pin review; regeneration
does not silently accept edited originals. `adaptations.json` describes the
boundary, and `expected-differences.json` lists the exact native-model exceptions.
