"""Tests for lib/iris-job.sh, the run-time steps every imaging job sources.

Asserts only on what a job shows: its exit status, its output and the run
directory. The missing-environment case runs anywhere. The full sequence
needs Katana's module system, so it runs only there, against the
environment whose Python runs the tests (the CPU job in the README of
envs/imaging/):

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s workflows/microct-2d-segmentation/tests
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[1]
REPO = WORKFLOW.parents[1]
JOB_LIB = REPO / "lib" / "iris-job.sh"
ON_KATANA = Path("/etc/profile.d/modules.sh").exists()


SYSTEM_CODE = Path("/srv/scratch/katana_ai/iris/code/workflows/microct-2d-segmentation")


def head(code=WORKFLOW):
    return subprocess.run(["git", "-C", str(code), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()


def source_job_lib(env_dir, run_dir, then="echo AFTER", commit="", code=WORKFLOW):
    """Run a job script's opening lines as the form writes them: set CODE,
    COMMIT (the clone's commit when the form rendered), ENV_DIR and RUN_DIR,
    turn on set -eo pipefail, source the library, then run `then`."""
    script = (
        'set -eo pipefail\n'
        f'CODE="{code}"\n'
        f'COMMIT="{commit}"\n'
        f'ENV_DIR="{env_dir}"\n'
        f'RUN_DIR="{run_dir}"\n'
        f'source "{JOB_LIB}"\n'
        f'{then}\n'
    )
    env = {k: v for k, v in os.environ.items() if k not in ("VIRTUAL_ENV", "PYTHONPATH")}
    return subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True, timeout=120)


class MissingEnvironment(unittest.TestCase):

    def test_stops_with_one_line_naming_the_path_and_the_contact(self):
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp, "envs", "imaging", "99")
            run_dir = Path(tmp, "dataset", "runs", "1")
            result = source_job_lib(env_dir, run_dir)
            self.assertNotEqual(result.returncode, 0)
            lines = (result.stdout + result.stderr).strip().splitlines()
            self.assertEqual(len(lines), 1, lines)
            self.assertIn(str(env_dir), lines[0])
            self.assertIn("patrick.tung@unsw.edu.au", lines[0])
            self.assertFalse(run_dir.exists())
            # PBS delivers the job output to runs/, so it must exist even here.
            self.assertTrue(run_dir.parent.is_dir())


@unittest.skipUnless(ON_KATANA, "needs Katana's module system")
class FullSequence(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.run_dir = Path(cls.tmp.name, "dataset", "runs", "1234")
        cls.result = source_job_lib(
            sys.prefix, cls.run_dir,
            then='echo "PYTHON=$(command -v python)"; python -c "import iris.volume, iris.labels; print(\'IMPORTS OK\')"')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_succeeds(self):
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)

    def test_activates_the_environment_with_lib_on_the_path(self):
        self.assertIn(f"PYTHON={sys.prefix}/bin/python", self.result.stdout)
        self.assertIn("IMPORTS OK", self.result.stdout)

    def test_records_the_clone_commit_in_the_run_directory(self):
        self.assertEqual((self.run_dir / "commit.txt").read_text().strip(), head())

    def test_exports_the_workflow_folder_for_the_entry_script(self):
        result = source_job_lib(sys.prefix, self.run_dir.with_name("1235"), then='echo "IRIS_CODE=$(printenv IRIS_CODE)"')
        self.assertIn(f"IRIS_CODE={WORKFLOW}\n", result.stdout)


@unittest.skipUnless(ON_KATANA, "needs Katana's module system")
class RenderTimeCommit(unittest.TestCase):
    """The embedded code dates from when the form rendered, lib/ from when
    the job starts (ADR-0006)."""

    def run_with(self, commit):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp, "dataset", "runs", "1")
            result = source_job_lib(sys.prefix, run_dir, commit=commit)
            files = {p.name: p.read_text().strip() for p in run_dir.iterdir()}
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result, files

    def test_the_render_time_commit_goes_to_commit_txt(self):
        result, files = self.run_with(head())
        self.assertEqual(files["commit.txt"], head())
        self.assertNotIn("lib_commit.txt", files)
        self.assertNotIn("WARNING", result.stdout + result.stderr)

    def test_a_clone_that_moved_since_rendering_is_recorded_as_lib_commit_with_a_warning(self):
        rendered = "0" * 40
        result, files = self.run_with(rendered)
        self.assertEqual(files["commit.txt"], rendered)
        self.assertEqual(files["lib_commit.txt"], head())
        self.assertIn("WARNING", result.stderr)
        self.assertIn(head(), result.stderr)

    def test_with_no_render_time_commit_the_clone_commit_at_job_start_is_recorded(self):
        _, files = self.run_with("")
        self.assertEqual(files["commit.txt"], head())
        self.assertNotIn("lib_commit.txt", files)


@unittest.skipUnless(ON_KATANA, "needs Katana's module system")
class ViewLines(unittest.TestCase):
    """The iris-view and iris-compare lines the job prints before and after
    training: the short forms `module load iris` gives from the system
    clone (ADR-0003), that clone's bin/ in full from any other."""

    def output(self, code):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp, "dataset", "runs", "1")
            result = source_job_lib(sys.prefix, run_dir, code=code, then="echo TRAINING; iris_done")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        before, after = result.stdout.split("TRAINING\n", 1)
        return before, after, run_dir

    def test_from_another_clone_the_job_prints_the_clones_full_paths(self):
        before, after, run_dir = self.output(WORKFLOW)
        for part in (before, after):
            self.assertIn(f"\n{REPO}/bin/iris-view {run_dir}\n", part)
            self.assertIn(f"\n{REPO}/bin/iris-compare\n", part)
            self.assertNotIn("module load iris", part)
        self.assertTrue(after.startswith("\nDone. "), after)
        self.assertTrue(after.endswith(f"\n{REPO}/bin/iris-compare\n"), after)

    @unittest.skipUnless(SYSTEM_CODE.is_dir(), "needs the system clone")
    def test_from_the_system_clone_the_job_prints_the_module_lines(self):
        before, after, run_dir = self.output(SYSTEM_CODE)
        for part in (before, after):
            self.assertIn(f"\nmodule load iris\niris-view {run_dir}\n", part)
            self.assertIn("\niris-compare\n", part)
            self.assertNotIn("/bin/iris-", part)
        self.assertTrue(after.endswith("\nmodule load iris\n" f"iris-view {run_dir}\n"
                                       "and compare your runs with:\niris-compare\n"), after)


if __name__ == "__main__":
    unittest.main()
