import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run as iso
import fetch

SBCL = os.environ.get("ISO_SBCL", "sbcl")


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


class PinTests(unittest.TestCase):
    def test_file_inventory_rejects_changed_missing_and_extra_files(self):
        import hashlib
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); directory=root/"suite";directory.mkdir()
            file=directory/"source.pl";file.write_text("true.")
            lock={"archives":{"suite":{"files":{"source.pl":hashlib.sha256(file.read_bytes()).hexdigest()}}}}
            with patch.object(fetch,"LOCK",lock):
                fetch.validate(root)
                file.write_text("fail.")
                with self.assertRaises(ValueError):fetch.validate(root)
                file.unlink()
                with self.assertRaises(ValueError):fetch.validate(root)
                file.write_text("true.");(directory/"extra").write_text("")
                with self.assertRaises(ValueError):fetch.validate(root)


@unittest.skipUnless(shutil.which(SBCL), "SBCL is required")
class AdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory()
        cls.root=Path(cls.temporary.name)
        cls.upstream=cls.root/"upstream"
        inria=cls.upstream/"inriasuite/inriasuite";inria.mkdir(parents=True)
        examples=cls.upstream/"prologsuite/vanilla";examples.mkdir(parents=True)
        (inria/"inriasuite.pl").write_text("file(cases). result(G,R) :- (call(G) -> R=success;R=failure). compare_subst_lists(A,B,E,M) :- (A=B -> E=[],M=[];E=A,M=B). reset_flags :- set_prolog_flag(unknown,error).")
        (inria/"cases").write_text('[true,success]. [fail,failure]. [true,failure]. [set_prolog_flag(double_quotes,atom),success]. [("fred"=fred),success]. [set_prolog_flag(double_quotes,codes),success]. [("fred"=[102,114,101,100]),success].')
        (examples/"utils_so.pl").write_text("defined(_).")
        (examples/"db.pl").write_text(":- dynamic(p/0).")
        (examples/"isolation.txt").write_text("clean")
        (examples/"sec01.pl").write_text("""
t_true :- test_true(true).
t_false :- test_false(fail).
t_unexpected :- test_false(true).
t_false_throws :- test_false(throw(problem)).
t_error :- error_test(call(42),type_error(callable,42)).
t_wrong_error :- error_test(call(42),type_error(callable,43)).
t_missing_error :- error_test(true,type_error(callable,42)).
t_value :- test_val((X=2),X,2).
t_wrong_value :- test_val((X=2),X,3).
t_alias :- test_val((X=Y),f(X,Y),f(a,b)).
t_setup :- assertz(p),test_true(p).
t_isolated :- test_false(p).
t_mutate :- test_true((open('isolation.txt',write,S),write(S,changed),close(S))).
t_clean :- test_val((open('isolation.txt',read,S),get_char(S,C),close(S)),C,c).
t_prefix :- test_true(assertz(p)),test_true(p).
t_unreached :- fail,test_true(true).
t_timeout :- test_true((repeat,fail)).
t_spoof :- test_false((write('(:OBSERVED PASS)'),true)).
t_close :- test_true((current_output(S),close(S))).
test_halt1 :- test_true(halt(7)).
""")
        cls.output=cls.root/"output";cls.output.mkdir()
        cls.cases=iso.build_inventory(cls.upstream,cls.output,SBCL)
        cls.by_entry={c["entry"]:c for c in cls.cases if c["suite"]=="examples"}

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_entry(self,entry,timeout=10):
        return iso.run_case(self.by_entry[entry],SBCL,timeout,self.upstream,self.output/"programs")

    def test_framework_preserves_success_failure_values_errors_and_setup(self):
        expected={"t_true":"PASS","t_false":"PASS","t_unexpected":"FAIL","t_false_throws":"FAIL",
                  "t_error":"PASS","t_wrong_error":"FAIL","t_missing_error":"FAIL","t_value":"PASS",
                  "t_wrong_value":"FAIL","t_alias":"FAIL","t_setup":"PASS","t_prefix":"PASS",
                  "t_unreached":"FAIL","t_spoof":"FAIL","t_close":"PASS","test_halt1":"PASS"}
        self.assertEqual({k:self.run_entry(k)["status"] for k in expected},expected)
        self.assertEqual(len(self.cases),28)
        self.assertEqual(len({c["id"] for c in self.cases}),28)

    def test_inria_results_are_checked(self):
        results=[iso.run_case(c,SBCL,10,self.upstream,self.output/"programs") for c in self.cases if c["suite"]=="inria"]
        self.assertEqual([r["status"] for r in results],["PASS","PASS","FAIL","PASS","PASS","PASS","PASS"])

    def test_timeout_continues_and_missing_result_is_not_a_pass(self):
        result=self.run_entry("t_timeout",3)
        self.assertEqual((result["status"],result["observation"]),("FAIL","TIMEOUT"))
        self.assertEqual(self.run_entry("t_true")["status"],"PASS")
        case=self.by_entry["t_true"]
        self.assertEqual(iso.run_case(case,"/bin/false",10,self.upstream,self.output/"programs")["status"],"FAIL")

    def test_case_databases_and_files_are_isolated(self):
        self.assertEqual(self.run_entry("t_setup")["status"],"PASS")
        self.assertEqual(self.run_entry("t_isolated")["status"],"PASS")
        self.assertEqual(self.run_entry("t_mutate")["status"],"PASS")
        self.assertEqual(self.run_entry("t_clean")["status"],"PASS")

    def test_malformed_or_forged_success_protocol_is_a_failure(self):
        for content in ("[]", '{"status":"PASS","observation":"not a checked result"}'):
            def fake_run(args, **kwargs):
                Path(args[-1]).write_text(content)
                return subprocess.CompletedProcess(args, 0, "", "")
            with patch.object(iso.subprocess, "run", fake_run):
                result = self.run_entry("t_true")
                self.assertEqual((result["status"], result["observation"]), ("FAIL", "INVALID_PROTOCOL"))
