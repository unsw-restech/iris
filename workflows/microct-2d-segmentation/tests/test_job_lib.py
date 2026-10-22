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


def source_job_lib(env_dir, run_dir, then="echo AFTER"):
    """Run a job script's opening lines as the form writes them: set CODE,
    ENV_DIR and RUN_DIR, turn on set -eo pipefail, source the library, then
    run `then`."""
    script = (
        'set -eo pipefail\n'
        f'CODE="{WORKFLOW}"\n'
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
        head = subprocess.run(["git", "-C", str(WORKFLOW), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
        self.assertEqual((self.run_dir / "commit.txt").read_text().strip(), head)

    def test_prints_the_clones_iris_view_and_iris_compare_lines(self):
        self.assertIn(f"\n{REPO}/bin/iris-view {self.run_dir}\n", self.result.stdout)
        self.assertIn(f"\n{REPO}/bin/iris-compare\n", self.result.stdout)


if __name__ == "__main__":
    unittest.main()
