#!/usr/bin/env python3
"""Run pinned upstream ISO cases; retain every PASS/FAIL/XFAIL/BLOCKED result."""
import argparse
import collections
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / "upstream.json").read_text())
REVISION = LOCK["revision"]


def lisp_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def run_case(case, sbcl, timeout):
    result = {k: v for k, v in case.items() if k not in ("program", "query")}
    result["query"] = case["query"]
    if case["blocked"]:
        return dict(result, status="BLOCKED", observation="; ".join(case["blocked"]))
    with tempfile.TemporaryDirectory(prefix="sprolog-iso-") as temp:
        root = Path(temp)
        job, output = root / "job.sexp", root / "result.sexp"
        job.write_text("(:program " + lisp_string(case["program"]) +
                       " :setup (" + " ".join(lisp_string(q) for q in case.get("setup", [])) + ")" +
                       " :query " + lisp_string(case["query"]) + ")", encoding="utf-8")
        start = time.monotonic()
        try:
            proc = subprocess.run([sbcl, "--noinform", "--control-stack-size", "1",
                                   "--script", str(HERE / "worker.lisp"), str(job), str(output)],
                                  cwd=root, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return dict(result, status="FAIL", observation="TIMEOUT", seconds=timeout)
        observation = output.read_text(encoding="utf-8") if output.exists() else "NO_RESULT"
        # PASS is a complete, exact protocol result, not a substring in an error.
        status = "PASS" if observation == "(:OBSERVED PASS)" and proc.returncode == 0 else "FAIL"
        if observation.startswith(("(:LOAD ", "(:PARSE ", "(:SETUP ")):
            status = "BLOCKED"
        return dict(result, status=status, observation=observation,
                    seconds=round(time.monotonic() - start, 3), exit_code=proc.returncode,
                    diagnostics=(proc.stdout + proc.stderr)[-4000:] if proc.returncode else "")


def attach_fixtures(cases, fixtures):
    """Replay declared predecessors in each fresh process, retaining isolation."""
    by_id = {c["id"]: c for c in cases}
    if set(fixtures) - set(by_id):
        raise ValueError("Unknown fixture case ID")

    def predecessors(case_id, active, seen, ordered):
        if case_id in active:
            raise ValueError("Cyclic fixture dependency: " + case_id)
        active.add(case_id)
        for previous in fixtures.get(case_id, []):
            if previous not in by_id or by_id[previous]["blocked"]:
                raise ValueError("Missing or blocked fixture predecessor: " + previous)
            if by_id[previous]["source"] != by_id[case_id]["source"]:
                raise ValueError("Fixture predecessor must use the same source program")
            if previous not in seen:
                predecessors(previous, active, seen, ordered)
                seen.add(previous)
                ordered.append(previous)
        active.remove(case_id)

    for case_id in fixtures:
        ordered = []
        predecessors(case_id, set(), set(), ordered)
        by_id[case_id]["predecessor_ids"] = ordered
        by_id[case_id]["setup"] = [by_id[previous]["query"] for previous in ordered]


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
    parser.add_argument("--upstream", type=Path, required=True, help="pinned Logtalk checkout")
    parser.add_argument("--sbcl", default="sbcl")
    parser.add_argument("--swipl", default="swipl", help="used only to parse the upstream test DSL")
    parser.add_argument("--output", type=Path, default=Path("iso-results"))
    parser.add_argument("--timeout", type=float, default=5)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--filter", default="")
    parser.add_argument("--strict", action="store_true", help="fail on FAIL or BLOCKED")
    parser.add_argument("--baseline", type=Path, help="gate changes against recorded observations")
    parser.add_argument("--expectations", type=Path, default=HERE / "expected-differences.json")
    args = parser.parse_args()
    root = args.upstream.resolve() / "tests" / "prolog"
    if not root.is_dir():
        parser.error("--upstream must contain tests/prolog")
    if args.timeout <= 0 or args.jobs <= 0:
        parser.error("--timeout and --jobs must be positive")
    hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(root.rglob("tests.lgt"))}
    if hashes != LOCK["files"]:
        raise ValueError("Upstream files differ from the pinned revision; no tests were run")
    args.output.mkdir(parents=True, exist_ok=True)
    inventory = args.output.resolve() / "cases.jsonl"
    subprocess.run([args.swipl, "-q", "-s", str(HERE / "import-logtalk.pl"), "--",
                    str(root), str(inventory)], check=True)
    cases = [json.loads(line) for line in inventory.read_text().splitlines()]
    ids = [c["id"] for c in cases]
    if not cases or len(ids) != len(set(ids)):
        raise ValueError("Empty or duplicate upstream case inventory")
    if len(cases) != LOCK["iso_cases"]:
        raise ValueError("Imported case count differs from the pinned inventory")
    attach_fixtures(cases, json.loads((HERE / "fixtures.json").read_text()))
    inventory.write_text("".join(json.dumps(c, ensure_ascii=False) + "\n" for c in cases))
    selected = [c for c in cases if args.filter in c["id"]]
    if not selected:
        raise ValueError("Filter selected no cases")
    # Populate the ASDF cache once before workers start; build failures are fatal.
    subprocess.run([args.sbcl, "--noinform", "--control-stack-size", "1", "--script",
                    str(HERE / "worker.lisp")], check=True, capture_output=True, text=True, timeout=60)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda c: run_case(c, args.sbcl, args.timeout), selected))
    expectations = json.loads(args.expectations.read_text())
    if args.filter:
        expectations = {k: v for k, v in expectations.items() if k in {r["id"] for r in results}}
    apply_expectations(results, expectations)
    regressions = []
    if args.baseline:
        baseline = json.loads(args.baseline.read_text())
        if args.filter:
            baseline = {k: v for k, v in baseline.items() if k in {r["id"] for r in results}}
        regressions = check_baseline(results, baseline)
    counts = dict(collections.Counter(r["status"] for r in results))
    report = {"upstream": "LogtalkDotOrg/logtalk3", "revision": REVISION,
              "profile": {"term_model": "native_cons", "read_syntax": "prolog", "write_syntax": "prolog"},
              "inventory": len(cases), "selected": len(selected), "counts": counts,
              "source_sha256": hashes, "regressions": regressions, "results": results}
    (args.output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    rows = ["# ISO compatibility observations", "", f"Upstream: Logtalk `{REVISION}`.", "",
            f"Inventory: {len(cases)}; selected: {len(selected)}; {counts}.", "",
            "Profile: native cons terms; READ/READ_TERM and WRITE predicates use Prolog syntax.", "",
            "These are finite test observations, not an ISO conformance percentage.", "",
            "| Case | Status | Observation |", "|---|---|---|"]
    for result in results:
        observation = result["observation"].replace("|", "\\|").replace("\n", " ")
        rows.append(f'| {result["id"]} | {result["status"]} | {observation} |')
    (args.output / "report.md").write_text("\n".join(rows) + "\n")
    print(json.dumps({"inventory": len(cases), "selected": len(selected), "counts": counts}))
    if regressions:
        print("Changed observations: " + ", ".join(regressions))
    return 1 if regressions or (args.strict and (counts.get("FAIL", 0) or counts.get("BLOCKED", 0))) else 0


if __name__ == "__main__":
    raise SystemExit(main())
