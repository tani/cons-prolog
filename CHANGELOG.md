# 0.5.0

- Rename project, ASDF systems and Lisp packages to sprolog.

- Replace forest-wide completion with dynamic SCC-local completion and local waiters. Recursive intra-SCC calls still use copied consumer continuations.
- Support CUT in tabled generators, untabled helpers and tabled DCGs when it does not cross an incomplete tabled subgoal.
- Add typed SLG-INCOMPLETE-CUT errors; check frozen alternatives using logical scope identities and rebase all copied physical cut boundaries.
- Preserve opaque PHRASE cut scopes across suspension and resumption.
- Abort cursors and release query-local tables on execution errors.
- Add completed-component, maximum-component-size and local-wait statistics.
- Add local-scheduling/cut regression cases with disabled and forced GC; retain independent WFS oracle coverage.

# 0.4.0

- Add suspension-based SLG variant tabling with query-local table space, answer deduplication, copied WAM consumer continuations, and a nonrecursive work queue.
- Add ground TNOT, delayed negative literals, conditional answers, simplification and well-founded three-valued results.
- Add TABLE/UNTABLE, QUERY :TRUTH-VALUES, extra NEXT-SOLUTION truth/delay values and SLG statistics.
- Support left-recursive tabled DCGs and mutual recursion; retain the sole granular WAM backend.
- Reject cyclic table terms, floundering, impure generator operations and changes during active tabled queries.
- Validate against an independent alternating fixed point for finite propositional programs, plus GC and dependency-depth tests.

# 0.3.1

- Rename DCG rule macros: `->` adds a rule and `-->` replaces rules of the same name and arity. Remove `-->>`.
- Update examples, documentation, and regression tests to use the new names.

# 0.3.0

- Adopt the granular WAM exclusively; remove reference backend and duplicate code storage.
- Remove :BACKEND arguments from QUERY and MAKE-QUERY.
- Add --> / -->> DCG definition macros and PHRASE/2,3 goal expansion.
- Add runtime Lisp PHRASE function and public DCG-EXPAND inspection API.
- Add terminals, epsilon, sequences, alternatives and semantic goals with lexical callbacks.
- Compile inline alternatives to branch choice points, retaining prefix side-effect semantics.
- Root saved branch environments during GC and restore them on backtracking.
- Keep grammar-rule cuts local and PHRASE expression cuts opaque to the caller.
- Hide fresh difference-list variables from query results and reject cyclic grammar controls.
- Add parsing, generation, semantic attributes, GC and deep-grammar regression tests.
- Add source-level execution coverage for all eighteen term instructions.

# 0.2.0

- Compile clause heads and body terms to granular WAM instruction families.
- Implement X/A aliasing, Y slots, read/write scans and environment deallocation.
- Add managed variable/cons heap mark/compact, including cyclic term graphs.
- Remap every surviving choice point's heap and trail restoration marks after GC.
- Trail only bindings requiring rollback; prune unreachable/dead undo records.
- Collect automatically at safe boundaries; support GC thresholds and manual GC.
- Release VM roots on exhausted queries as well as explicit cursor close.
- Keep a reference backend for differential validation.
- Expand verification to 820 checks, including bounded heap stress tests.

QUERY and MAKE-QUERY gain :BACKEND and :GC-THRESHOLD keywords.
COLLECT-QUERY-GARBAGE is exported. QUERY-STATISTICS now reports managed cells
(variables and cons cells), allocation totals, Trail and GC counters.

# 0.1.0

Initial S-expression API, explicit-control VM, template-based term processing,
lexical callbacks, clause replacement and 27 semantic/stack-safety checks.
