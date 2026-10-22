# Shared-source comparison with SWI-Prolog

Measured 2026-10-23 JST, starting from upstream `9e14c1e` (0.10.0).
All six workloads beat SWI-Prolog 9.2.9 with `-O` on this host after warmup.
This is a throughput result for this suite, not a claim about every Prolog program.

| Workload | Upstream ms | Optimized ms | SWI `-O` ms | SWI / optimized |
| --- | ---: | ---: | ---: | ---: |
| 8 queens, all 92 solutions | 243.975 | 1.080 | 2.564 | 2.38x |
| Takeuchi (16, 10, 4) | 378.788 | 1.061 | 3.971 | 3.74x |
| Naive reverse, 1,200 elements | 2202.894 | 12.974 | 22.075 | 1.70x |
| Quicksort, 2,000 elements | 264.484 | 1.130 | 4.018 | 3.55x |
| Binary graph: 2,046 edges, 1,024 length-10 paths | 841.005 | 0.183 | 0.354 | 1.93x |
| Symbolic differentiation, depth 8; 12,799 result nodes | 78.147 | 0.392 | 0.924 | 2.36x |

## Method

- Linux x86-64, AMD EPYC 9V74, nine visible logical CPUs, eight-CPU quota and 8 GiB memory limit. Queries are single-threaded.
- SBCL 2.2.9.debian, 2 GiB dynamic space, 1 MiB control stack. SWI-Prolog 9.2.9, optimized compilation enabled with `-O`.
- Both engines load the exact same `competitive.pl` and `competitive-edges.pl`. Algorithms, inputs, clause order, arithmetic and answer enumeration are shared; there are no Lisp callbacks, CLP libraries or solver-specific benchmark definitions.
- One untimed query warms the compiler and indexes. Each of five timed samples executes a fixed batch, identical for both engines: queens/tak/qsort 100; reverse 10; graph 500; differentiation 250. Times above are median CPU seconds divided by the batch size.
- Query creation, execution, scalar result export and cursor teardown are inside the sprolog timed loop. Both engines check the result of every query. Expected results are independently fixed in `compare.py`: 92, 5, 1200, 2000, 1024 and 12799.
- Full host GC is requested before each sample, outside timing. GC during the workload remains included. Engines run serially. No terminal I/O occurs inside the timed loop.
- Process launch, source loading, database construction and initial native compilation are excluded. The raw `cold_seconds` field records first-query time; the first benchmark compiles a closed group containing all six `bench/2` clauses, so later first-query values are not independent cold-compiler measurements.
- Upstream uses the same source and runner, five single-query samples after a warmup (`BENCH_BATCH=1`). Its column provides historical context; the parity comparison uses the identical batched protocol for the optimized engine and SWI.
- Raw CPU samples, allocation counts, batches, versions and executed commands are in [competitive-results.json](../benchmarks/competitive-results.json). Allocation bytes are cumulative SBCL allocations per query, not live bytes or RSS. SWI allocation fields are placeholders (zero), not allocation measurements.

## Reproduction

From the repository root, with SBCL, SWI-Prolog and Python 3 available:

```sh
sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
python3 benchmarks/compare.py --require-parity
```

`--sbcl`, `--swipl`, `--repeats` and `--output` select executables and output. The parity flag fails if any measured median is slower than SWI. Other hardware/runtime versions may produce different ratios.

To compare the interpreter path or individual cases:

```sh
SPROLOG_DISABLE_NATIVE=1 sbcl --dynamic-space-size 2048 --control-stack-size 1 --script tests/run.lisp
BENCH_CASE=QUEENS BENCH_BATCH=1 sbcl --dynamic-space-size 2048 --control-stack-size 1 --script benchmarks/competitive.lisp
BENCH_CASE=QUEENS BENCH_BATCH=1 swipl -O -q -s benchmarks/competitive-swi.pl
```

## Implementation and limits

First-argument indexing skips impossible scalar/cons heads while merging variable heads in source order. Choice points retain immutable code snapshots. Predicates with more than 32 wildcard heads use linear dispatch to avoid quadratic index replication.

Scalar unification avoids graph machinery. Graph unification retains rational-tree pair tracking. Graph copying uses an explicit task vector and retains the original preorder, sharing and cycles.

On SBCL, `src/syntax/native.lisp` specializes pure user predicates by their ground input positions. Disjoint input heads or source cuts justify deterministic/semideterministic execution. Native Common Lisp labels perform integer arithmetic, matching and calls directly. A pure statically known `findall/3` goal uses continuation-based enumeration; ground fact relations use indexes on available scalar inputs. These optimizations depend on program structure and call modes, not benchmark names.

Native calls require ground acyclic inputs and independent free output variables. Constrained/aliased outputs, unsupported arithmetic types, host callbacks, effects, tabling and instrumentation retain the VM path. Compiled and rejected modes are cached per database generation; clearing a database releases its cache. Recursive native collector compilation is detected and falls back.

Native evaluation is speculative: it makes no VM bindings or external effects before completion. Depth (2,048), call fuel (1,000,000), compiler mode count (128), template depth (64) and collector answer count (65,536) bounds trigger VM fallback. A cursor remembers a failed specialization to avoid retrying the same expensive bailout at every recursive call. The portable WAM remains the implementation for other Lisp runtimes; SLG is not a speed claim of this benchmark.

`query-statistics` adds `:native-calls` and `:native-deoptimizations`. Existing instruction, continuation-depth and managed-cell counters describe WAM work; native temporary allocation is visible in the host byte counters.

## Correctness evidence

4,625 checks pass on SBCL with a 1 MiB stack, including native/interpreter comparisons, 49 cut/guard combinations, errors, output constraints/aliasing, rational/open terms, recursive collectors, cache invalidation and deep tail/non-tail fallback. With native execution disabled, 4,618 checks pass (seven native-path assertions are skipped). All 54 serialized derived observations match the upstream revision. Existing SLG, callback, forced-GC and logical-update regressions remain enabled.
