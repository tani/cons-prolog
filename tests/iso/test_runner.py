import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import run as iso

SBCL = os.environ.get("ISO_SBCL", "sbcl")
SWIPL = os.environ.get("ISO_SWIPL", "swipl")


class ReportingTests(unittest.TestCase):
    def test_expected_difference_requires_exact_failure(self):
        expectations = {"a": {"reason": "native term model", "observation": "different"}}
        for status, observed, expected in [
            ("FAIL", "different", "XFAIL"),
            ("FAIL", "another", "FAIL"),
            ("PASS", "(:OBSERVED PASS)", "FAIL"),
            ("BLOCKED", "different", "FAIL"),
        ]:
            results = [{"id": "a", "status": status, "observation": observed}]
            iso.apply_expectations(results, expectations)
            self.assertEqual(results[0]["status"], expected)
            self.assertEqual(bool(results[0].get("expectation_changed")), expected == "FAIL")

    def test_stale_or_unexplained_difference_is_an_error(self):
        with self.assertRaises(ValueError):
            iso.apply_expectations([], {"missing": {"reason": "x", "observation": "x"}})
        with self.assertRaises(ValueError):
            iso.apply_expectations([{"id": "a"}], {"a": {"observation": "x"}})

    def test_baseline_rejects_missing_cases_and_regressions(self):
        baseline = {"a": {"status": "PASS", "observation": "(:OBSERVED PASS)"}}
        with self.assertRaises(ValueError):
            iso.check_baseline([], baseline)
        self.assertEqual(iso.check_baseline(
            [{"id": "a", "status": "FAIL", "observation": "bad"}], baseline), ["a"])

    def test_baseline_accepts_improvement(self):
        self.assertEqual(iso.check_baseline(
            [{"id": "a", "status": "PASS", "observation": "(:OBSERVED PASS)"}],
            {"a": {"status": "BLOCKED", "observation": "unadapted"}}), [])

    def test_fixture_dependencies_are_ordered_and_validated(self):
        cases = [{"id": x, "source": "tests.lgt", "blocked": [], "query": x} for x in "abcd"]
        iso.attach_fixtures(cases, {"c": ["a", "b"], "d": ["c"]})
        self.assertEqual(cases[-1]["predecessor_ids"], ["a", "b", "c"])
        self.assertEqual(cases[-1]["setup"], ["a", "b", "c"])
        for fixtures in ({"missing": []}, {"b": ["missing"]}, {"b": ["a"], "a": ["b"]}):
            with self.assertRaises(ValueError):
                iso.attach_fixtures(cases, fixtures)
        cases[0]["blocked"] = ["unsupported fixture"]
        with self.assertRaises(ValueError):
            iso.attach_fixtures(cases, {"b": ["a"]})


@unittest.skipUnless(shutil.which(SBCL) and shutil.which(SWIPL), "SBCL and SWI are required")
class AdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run([SBCL, "--noinform", "--control-stack-size", "1", "--script",
                        str(iso.HERE / "worker.lisp")], check=True, capture_output=True)

    def test_upstream_framework_semantics_and_data_round_trip(self):
        source = r"""
:- dynamic([empty_a/0,empty_b/1]).
holds({a}).
member(X,[X|_]).
member(X,[_|Xs]) :- member(X,Xs).
test(iso_true, true) :- {true}.
test(iso_false, false) :- {fail}.
test(iso_error, error(type_error(callable,42))) :- {call(42)}.
test(iso_wrong_error, error(type_error(callable,43))) :- {call(42)}.
test(iso_bad_post, true(false)) :- {true}.
test(iso_not_false, false) :- {true}.
test(iso_variant, variant(T,foo(_,_,_))) :- {functor(T,foo,3)}.
test(iso_aliasing, variant(foo(X,X),foo(_,_))) :- true.
test(iso_data, true(T == {a})) :- {holds(T)}.
test(iso_atom, true(T == [']',','])) :- {T = [']',',']}.
test(iso_empty, false) :- {empty_a}.
test(iso_assertion) :- assertion(fail).
test(iso_fixture, true(T == 123)) :- ^^set_text_input('123. '), {read(T)}.
test(iso_continuation, true(N == 3)) :- {atom_length('a\
 b',N)}.
test(iso_exists, exists(X == 2)) :- {member(X,[1,2])}.
test(iso_no_exists, exists(X == 3)) :- {member(X,[1,2])}.
test(iso_ball, ball(hello)) :- {throw(hello)}.
test(iso_wrong_ball, ball(other)) :- {throw(hello)}.
test(iso_subsumes, subsumes(foo(_),T)) :- {T=foo(a)}.
test(iso_fail_alias, fail) :- fail.
:- if(unknown_condition).
test(iso_conditional, true) :- true.
:- endif.
- test(iso_disabled, true) :- true.
test(iso_options, true, [condition(true)]) :- true.
"""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "tests.lgt").write_text(source)
            inventory = root / "cases.jsonl"
            subprocess.run([SWIPL, "-q", "-s", str(iso.HERE / "import-logtalk.pl"), "--",
                            str(root), str(inventory)], check=True, capture_output=True)
            cases = [json.loads(line) for line in inventory.read_text().splitlines()]
        self.assertEqual(len(cases), 23)
        results = {c["name"]: iso.run_case(c, SBCL, 10) for c in cases}
        expected = {
            "iso_true": "PASS", "iso_false": "PASS", "iso_error": "PASS",
            "iso_wrong_error": "FAIL", "iso_bad_post": "FAIL", "iso_not_false": "FAIL",
            "iso_variant": "PASS", "iso_aliasing": "FAIL", "iso_data": "PASS", "iso_atom": "PASS",
            "iso_empty": "PASS", "iso_assertion": "FAIL", "iso_fixture": "PASS",
            "iso_continuation": "PASS", "iso_conditional": "BLOCKED",
            "iso_exists": "PASS", "iso_no_exists": "FAIL", "iso_ball": "PASS",
            "iso_wrong_ball": "FAIL", "iso_subsumes": "PASS", "iso_fail_alias": "PASS",
            "iso_disabled": "BLOCKED", "iso_options": "BLOCKED",
        }
        self.assertEqual({k: v["status"] for k, v in results.items()}, expected,
                         {k: v["observation"] for k, v in results.items() if v["status"] != expected[k]})

    def test_case_timeout_does_not_prevent_next_case(self):
        case = {"id": "a", "blocked": [], "program": "", "query": "repeat,fail."}
        result = iso.run_case(case, SBCL, 0.5)
        self.assertEqual((result["status"], result["observation"]), ("FAIL", "TIMEOUT"))
        case["query"] = "iso_test_result(pass)."
        self.assertEqual(iso.run_case(case, SBCL, 10)["status"], "PASS")

    def test_missing_result_and_process_failure_are_not_passes(self):
        case = {"id": "a", "blocked": [], "program": "", "query": "true."}
        self.assertEqual(iso.run_case(case, SBCL, 10)["status"], "FAIL")
        self.assertEqual(iso.run_case(case, "/bin/false", 10)["status"], "FAIL")

    def test_fixture_replay_preserves_case_isolation_and_reports_failure(self):
        case = {"id": "a", "blocked": [], "program": "p.",
                "setup": ["retract(p),iso_test_result(pass)."],
                "query": "(p -> iso_test_result(fail); iso_test_result(pass))."}
        self.assertEqual(iso.run_case(case, SBCL, 10)["status"], "PASS")
        case["setup"] = []
        case["query"] = "p,iso_test_result(pass)."
        self.assertEqual(iso.run_case(case, SBCL, 10)["status"], "PASS")
        case["setup"] = ["iso_test_result(fail)."]
        self.assertEqual(iso.run_case(case, SBCL, 10)["status"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
