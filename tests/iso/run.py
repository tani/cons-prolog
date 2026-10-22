#!/usr/bin/env python3
"""Run the hash-pinned Hodgson ISO suites with SBCL/sprolog only."""
import argparse
import collections
import concurrent.futures
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from fetch import LOCK, validate
HERE = Path(__file__).resolve().parent


def lisp_string(text):
    return '"' + str(text).replace('\\', '\\\\').replace('"', '\\"') + '"'


def build_inventory(upstream, output, sbcl):
    proc = subprocess.run([sbcl, "--noinform", "--control-stack-size", "1", "--script",
                    str(HERE / "worker.lisp"), "inventory", str(upstream), str(output)],
                   capture_output=True, text=True, timeout=60)
    if proc.returncode:
        raise RuntimeError("Inventory build failed:\n" + proc.stdout[-2000:] + proc.stderr[-4000:])
    cases = json.loads((output / "cases.json").read_text())
    if not cases or len({c["id"] for c in cases}) != len(cases):
        raise ValueError("Empty or duplicate case inventory")
    return cases


def run_case(case, sbcl, timeout, upstream, programs):
    with tempfile.TemporaryDirectory(prefix="sprolog-hodgson-") as temporary:
        root = Path(temporary)
        fixture_source = upstream / ("inriasuite/inriasuite" if case["suite"] == "inria" else "prologsuite/vanilla")
        shutil.copytree(fixture_source, root, dirs_exist_ok=True)
        fields = {"id": case["id"], "suite": case["suite"], "source": case["source"],
                  "program": programs / case["program"], "entry": case["entry"]}
        if "ordinal" in case:
            fields["ordinal"] = case["ordinal"]
        job, result = root / "job.sexp", root / "result.json"
        job.write_text("(" + " ".join(":" + k + " " + lisp_string(v) for k,v in fields.items()) + ")")
        start = time.monotonic()
        try:
            proc = subprocess.run([sbcl, "--noinform", "--control-stack-size", "1", "--script",
                                   str(HERE / "worker.lisp"), "run", str(job), str(result)],
                                  cwd=root, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return dict(case, status="FAIL" if (root / "started.json").exists() else "BLOCKED",
                        observation="TIMEOUT", seconds=timeout)
        if case["entry"] == "test_halt1" and (root / "started.json").exists() and proc.returncode == 7:
            observation = {"status": "PASS", "observation": "HALT_EXIT_7"}
        elif result.exists() and proc.returncode == 0:
            try:
                observation = json.loads(result.read_text())
                if not isinstance(observation, dict) or observation.get("status") not in {"PASS", "FAIL", "SKIP", "BLOCKED"}:
                    raise ValueError("Invalid status")
                if observation["status"] == "PASS" and observation.get("observation") != "(:OBSERVED PASS)":
                    raise ValueError("Invalid success result")
            except (ValueError, TypeError):
                observation = {"status": "FAIL", "observation": "INVALID_PROTOCOL"}
        else:
            observation = {"status": "FAIL", "observation": "NO_RESULT"}
        return dict(case, **observation, seconds=round(time.monotonic()-start,3),
                    exit_code=proc.returncode, diagnostics=(proc.stdout+proc.stderr)[-4000:] if proc.returncode else "")


def apply_expectations(results, expectations):
    by_id = {r["id"]: r for r in results}
    unknown = set(expectations) - set(by_id)
    if unknown:
        raise ValueError("Stale expected differences: " + ", ".join(sorted(unknown)))
    for case_id, expected in expectations.items():
        if not expected.get("reason") or not expected.get("observation"):
            raise ValueError("Expected differences require a reason and exact observation: " + case_id)
        result = by_id[case_id]
        result["difference_reason"] = expected["reason"]
        if result["status"] == "FAIL" and result["observation"] == expected["observation"]:
            result["status"] = "XFAIL"
        else:
            result["status"] = "FAIL"
            result["expectation_changed"] = True


def check_baseline(results, baseline):
    current = {r["id"]: r for r in results}
    if set(current) != set(baseline):
        raise ValueError("Baseline and selected case IDs differ")
    regressions = []
    for case_id, result in current.items():
        previous = baseline[case_id]
        if result.get("expectation_changed"):
            regressions.append(case_id)
        elif result["status"] == "PASS":
            continue
        elif (result["status"], result["observation"]) != (previous["status"], previous["observation"]):
            regressions.append(case_id)
    return regressions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True, help="hash-pinned Hodgson distributions")
    parser.add_argument("--sbcl", default="sbcl")
    parser.add_argument("--output", type=Path, default=Path("iso-results"))
    parser.add_argument("--timeout", type=float, default=5)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--filter", default="")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--expectations", type=Path, default=HERE / "expected-differences.json")
    args = parser.parse_args()
    if args.timeout <= 0 or args.jobs <= 0:
        parser.error("--timeout and --jobs must be positive")
    upstream, output = args.upstream.resolve(), args.output.resolve()
    validate(upstream)
    output.mkdir(parents=True, exist_ok=True)
    cases = build_inventory(upstream, output, args.sbcl)
    if len(cases) != LOCK["cases"]:
        raise ValueError("Case count differs from pinned inventory")
    selected = [c for c in cases if args.filter in c["id"]]
    if not selected:
        raise ValueError("Filter selected no cases")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda c: run_case(c, args.sbcl, args.timeout, upstream, output / "programs"), selected))
    selected_ids = {r["id"] for r in results}
    expectations = json.loads(args.expectations.read_text())
    if args.filter:
        expectations = {k: v for k, v in expectations.items() if k in selected_ids}
    apply_expectations(results, expectations)
    regressions = []
    if args.baseline:
        baseline = json.loads(args.baseline.read_text())
        if args.filter:
            baseline = {k: v for k, v in baseline.items() if k in selected_ids}
        regressions = check_baseline(results, baseline)
    counts = dict(collections.Counter(r["status"] for r in results))
    report = {"upstream": LOCK, "adaptations": json.loads((HERE / "adaptations.json").read_text()),
              "inventory": len(cases), "selected": len(selected), "counts": counts,
              "profile": {"term_model": "native_cons", "read_syntax": "prolog", "write_syntax": "prolog"},
              "regressions": regressions, "results": results}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    rows = ["# Hodgson ISO observations", "", str(counts), "",
            "| Case | Status | Observation |", "|---|---|---|"]
    for result in results:
        observation = result["observation"].replace("|", "\\|").replace("\n", " ")
        rows.append(f'| {result["id"]} | {result["status"]} | {observation} |')
    (output / "report.md").write_text("\n".join(rows) + "\n")
    print(json.dumps({"inventory": len(cases), "selected": len(selected), "counts": counts}))
    if regressions:
        print("Changed observations: " + ", ".join(regressions))
    return int(bool(regressions or (args.strict and (counts.get("FAIL", 0) or counts.get("BLOCKED", 0)))))


if __name__ == "__main__":
    raise SystemExit(main())
