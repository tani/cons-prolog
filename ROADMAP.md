# Implementation roadmap

## Completed (0.5.0)

- Independent Common Lisp implementation and ASDF integration.
- S-expression compiler; X/A aliasing and Y environment slots.
- get/put/list/structure/constant/value/variable term families.
- unify/set families with read/write scan state and anonymous VOID instructions.
- Explicit choices, continuations, environment deallocation and tail execution.
- Iterative rational-tree unification, graph copying and cyclic source compilation.
- Nonmoving VM ownership-vector mark/compact for variables and cons cells.
- Roots from registers, all suspended continuations, choices, query variables and scans.
- Conditional trailing, dead undo pruning and remapped heap/trail choice-point marks.
- Adaptive automatic GC and a public manual collection API.
- One granular WAM execution backend; GC-disabled vs enabled regression runs.
- DCG difference-list expansion, hygienic hidden variables and PHRASE/2,3.
- Terminal sequences, semantic goals with lexical callbacks and inline disjunction.
- Branch choice points with saved Y environments and GC roots.
- Predicate-local DCG cuts and opaque PHRASE expression cut scopes.
- Query cursors, copied answers and lexical Lisp callbacks.
- Suspension-based SLG variant tabling; copied consumer continuations and queue scheduling.
- Ground delayed negation and well-founded conditional answers with truth/delay API.
- Dynamic SCC-local completion, local waiters and recursive cycle consumers.
- XSB-style cut checks across unfinished tables; logical scope identities survive copies.
- Ordinary helper and completed-table cuts, DCG/PHRASE scope preservation.
- Query-local table teardown, fail-closed cursors, host-operation guards and version checks.
- Left-recursive tabled DCGs and independent alternating-fixed-point validation.

## Next: selected Allegro API compatibility

Independent behavior specification from public documentation and a compatibility
matrix; interactive queries, variable inspection, call and control goals,
assert/retract, collectors, cleanup scopes. Lisp UNWIND-PROTECT alone is insufficient
for resource cleanup across Prolog backtracking; this needs a separate design.

## Later: performance

Shared frozen stacks, answer tries, call/answer subsumption, table-space accounting,
more efficient incremental SCC maintenance and immediate completion of ground
successes. Current SLG copies continuations and recomputes SCCs iteratively.


First-argument indexing, reusable X registers, lifetime analysis to move suitable
Y variables to X registers, direct acyclic term construction without graph
placeholders, compact instruction encodings and native dispatch within one Lisp
function. Preserve the explicit VM control model and run the differential tests.

The VM deliberately retains Lisp cons graph representation rather than a contiguous
classic WAM tagged-cell heap. Physical memory reclamation remains the host GC's job.
