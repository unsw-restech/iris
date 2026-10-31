"""Tests for iris.rundir, the run directory module: recording a run's code
into a run directory in a scratch git clone, as lib/iris-job.sh's
iris_record_code does, and reading back its commit and whether it is an
edited run. Run from the repo root in the desktop CPU venv:

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s lib/tests
"""

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from run_dirs import COMMITTED, ENTRY, clone_with_entry, finished_run, move_clone, record_code  # puts lib/ on the path

from iris.record import RunRecord  # noqa: E402


class RecordCode(unittest.TestCase):

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.code, self.commit = clone_with_entry(self.tmp)
        self.run_dir = self.tmp / "dataset" / "runs" / "1234"

    def files(self):
        return {p.name: p.read_text() for p in self.run_dir.iterdir()}

    def test_an_unedited_run_records_its_commit_and_an_empty_diff(self):
        result = record_code(self.run_dir, self.code, self.commit)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.files(), {"run.py": COMMITTED, "commit.txt": self.commit + "\n", "run.diff": ""})
        self.assertEqual(result.stdout, f"run.py is {ENTRY} at commit {self.commit}, unedited.\n")
        self.assertEqual(result.stderr, "")

    def test_an_edited_run_writes_and_prints_its_diff_against_the_commit(self):
        result = record_code(self.run_dir, self.code, self.commit, run_py="print('edited')\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        diff = ("--- a/workflows/microct-2d-segmentation/src/run.py\n"
                "+++ b/workflows/microct-2d-segmentation/src/run.py\n"
                "@@ -1 +1 @@\n-print('as committed')\n+print('edited')\n")
        self.assertEqual(self.files(), {"run.py": "print('edited')\n", "commit.txt": self.commit + "\n", "run.diff": diff})
        self.assertTrue(result.stdout.startswith("EDITED RUN: "), result.stdout)
        self.assertIn(f"differs from {ENTRY} at commit {self.commit}", result.stdout)
        self.assertIn("Load parameters", result.stdout)
        self.assertIn("set the form's fields first and edit the code last", result.stdout)
        self.assertTrue(result.stdout.endswith(diff + "\n"), result.stdout)
        self.assertEqual(result.stderr, "")

    def test_with_no_commit_the_clones_commit_now_is_recorded_and_edited_is_unknown(self):
        result = record_code(self.run_dir, self.code, None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.files(), {"run.py": COMMITTED, "commit.txt": self.commit + "\n"})
        self.assertEqual(result.stderr.count("WARNING"), 2, result.stderr)
        self.assertIn(f"commit.txt holds its commit at job start, {self.commit}", result.stderr)
        self.assertIn("edited is unknown", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_a_commit_git_cannot_read_is_recorded_and_edited_is_unknown(self):
        unreadable = "0123456789abcdef0123456789abcdef01234567"
        result = record_code(self.run_dir, self.code, unreadable)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.files(), {"run.py": COMMITTED, "commit.txt": unreadable + "\n",
                                        "lib_commit.txt": self.commit + "\n"})
        self.assertIn("WARNING", result.stderr)
        self.assertIn("edited is unknown", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_a_clone_that_moved_since_rendering_records_lib_commit_with_a_warning(self):
        moved = move_clone(self.code)
        result = record_code(self.run_dir, self.code, self.commit)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.files(), {"run.py": COMMITTED, "commit.txt": self.commit + "\n",
                                        "lib_commit.txt": moved + "\n", "run.diff": ""})
        self.assertEqual(result.stderr.count("WARNING"), 1, result.stderr)
        self.assertIn(f"moved from commit {self.commit}", result.stderr)
        self.assertIn(f"to {moved}", result.stderr)
        self.assertIn(str(self.run_dir / "lib_commit.txt"), result.stderr)

    def test_a_record_that_cannot_be_written_warns_and_does_not_fail(self):
        self.run_dir.mkdir(parents=True)
        for name in ("commit.txt", "run.diff"):
            (self.run_dir / name).mkdir()  # a folder can't be replaced by a file
        result = record_code(self.run_dir, self.code, self.commit)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr.count("WARNING"), 2, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("unedited", result.stdout)


class RunJson(unittest.TestCase):
    """What the run record (RunRecord) reads back from a run directory whose
    code was recorded: run.json's commit tags and its edited flag."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.code, self.commit = clone_with_entry(self.tmp)

    def run_json(self, commit, **kwargs):
        run_dir = finished_run(self.tmp / "iris", self.tmp / "dataset" / "runs" / "1234", self.code, commit, **kwargs)
        return json.loads((run_dir / "run.json").read_text())

    def test_an_unedited_run(self):
        run = self.run_json(self.commit)
        self.assertIs(run["edited"], False)
        self.assertEqual(run["tags"]["commit"], self.commit)
        self.assertNotIn("lib_commit", run["tags"])

    def test_an_edited_run_in_a_clone_that_moved(self):
        moved = move_clone(self.code)
        run = self.run_json(self.commit, run_py="print('edited')\n")
        self.assertIs(run["edited"], True)
        self.assertEqual(run["tags"]["commit"], self.commit)
        self.assertEqual(run["tags"]["lib_commit"], moved)

    def test_a_run_whose_edits_are_unknown_writes_unknown(self):
        run = self.run_json(None)
        self.assertEqual(run["edited"], "unknown")
        self.assertEqual(run["tags"]["commit"], self.commit)

    def test_a_run_whose_code_was_never_recorded_records_the_clones_commit(self):
        run_dir = self.tmp / "dataset" / "runs" / "1"
        with mock.patch.dict(os.environ, IRIS_HOME=str(self.tmp / "iris")), \
                RunRecord(run_dir, "bone", self.code) as record:
            record.write_params({})
        run = json.loads((run_dir / "run.json").read_text())
        self.assertEqual(run["tags"]["commit"], self.commit)
        self.assertEqual(run["edited"], "unknown")


if __name__ == "__main__":
    unittest.main()
