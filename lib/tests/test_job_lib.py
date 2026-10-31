"""Tests for lib/iris-job.sh, the run-time steps every imaging job sources.

Asserts only on what a job shows: its exit status, its output and the run
directory. The missing-environment case runs anywhere. The full sequence
needs Katana's module system, so it runs only there, against the
environment whose Python runs the tests (the CPU job in the README of
envs/imaging/). Each job starts with the header the reference form
renders (lib/tests/form_helper.rb, so Ruby is needed), its CODE the
reference workflow's folder in the clone that serves the form:

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s lib/tests
"""

import functools
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / "workflows" / "microct-2d-segmentation"
JOB_LIB = REPO / "lib" / "iris-job.sh"
FORM_HELPER = REPO / "lib" / "tests" / "form_helper.rb"
ON_KATANA = Path("/etc/profile.d/modules.sh").exists()


SYSTEM_CODE = Path("/srv/scratch/katana_ai/iris/code/workflows/microct-2d-segmentation")


def head(code=WORKFLOW):
    return subprocess.run(["git", "-C", str(code), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()


def rendered_script(code, dataset):
    """The job script the reference form renders, served from the clone
    holding `code`, for `dataset` and the form's defaults."""
    return subprocess.run(
        ["ruby", str(FORM_HELPER), "--apps-dir", str(code.parent), "--no-check", str(WORKFLOW / "form.yml.erb"),
         f"dataset={dataset}"],
        capture_output=True, text=True, check=True).stdout


@functools.cache
def record_step():
    """The rendered script's line after the heredoc that writes run.py: the
    call recording the run's code."""
    script = rendered_script(WORKFLOW, "/srv/scratch/z0000000/dataset")
    marker = re.search(r"<<'(\w+)'\n", script).group(1)
    return script.split(f"\n{marker}\n", 1)[1].splitlines()[0]


def source_job_lib(env_dir, run_dir, then="echo AFTER", commit=None, code=WORKFLOW):
    """Run the rendered script's header, from #!/bin/bash to sourcing the
    library, for a run directory <dataset>/runs/<job>, then run `then`.
    ENV_DIR is `env_dir`; COMMIT, the clone's commit when the form
    rendered, is `commit` if given. The library sourced is always this
    tree's, whichever clone `code` is in."""
    assert run_dir.parent.name == "runs", run_dir
    lines = rendered_script(code, run_dir.parent.parent).splitlines(keepends=True)
    end = next(i for i, line in enumerate(lines) if JOB_LIB.name in line)
    header = "".join(lines[:end]) + f'source "{JOB_LIB}"\n'
    for name, value in {"ENV_DIR": env_dir, "COMMIT": commit}.items():
        if value is not None:
            line = f'{name}="{value}"'
            header, n = re.subn(rf"^{name}=.*$", lambda _, line=line: line, header, flags=re.M)
            assert n == 1, f"the rendered header sets {name} {n} times"
    env = {k: v for k, v in os.environ.items() if k not in ("VIRTUAL_ENV", "PYTHONPATH")}
    env["PBS_JOBID"] = f"{run_dir.name}.kman.restech.unsw.edu.au"
    return subprocess.run(["bash", "-c", f"{header}{then}\n"], env=env, capture_output=True, text=True, timeout=120)


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

    def test_the_header_shows_the_clones_commit_the_environment_and_the_run_directory(self):
        self.assertIn(f"\nCommit      : {head()}\n", self.result.stdout)
        self.assertIn(f"\nEnvironment : {sys.prefix}\n", self.result.stdout)
        self.assertIn(f"\nRun dir     : {self.run_dir}\n", self.result.stdout)

    def test_records_no_code_before_the_script_calls_iris_record_code(self):
        self.assertEqual(list(self.run_dir.iterdir()), [])

    def test_exports_the_workflow_folder_for_the_entry_script(self):
        result = source_job_lib(sys.prefix, self.run_dir.with_name("1235"), then='echo "IRIS_CODE=$(printenv IRIS_CODE)"')
        self.assertIn(f"IRIS_CODE={WORKFLOW}\n", result.stdout)


@unittest.skipUnless(ON_KATANA, "needs Katana's module system")
class RenderTimeCommit(unittest.TestCase):
    """The embedded code dates from when the form rendered, lib/ from when
    the job starts (ADR-0006): iris_record_code records both."""

    def run_with(self, commit):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp, "dataset", "runs", "1")
            result = source_job_lib(sys.prefix, run_dir, commit=commit, then=(
                f'cp "{WORKFLOW / "src" / "run.py"}" "$RUN_DIR/run.py"\n'
                f'{record_step()}'))
            files = {p.name: p.read_text().strip() for p in run_dir.iterdir()}
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result, files

    def test_the_render_time_commit_goes_to_commit_txt_and_the_header(self):
        result, files = self.run_with(head())
        self.assertEqual(files["commit.txt"], head())
        self.assertNotIn("lib_commit.txt", files)
        self.assertIn("run.diff", files)
        self.assertIn(f"\nCommit      : {head()}\n", result.stdout)
        self.assertNotIn("WARNING", result.stdout + result.stderr)

    def test_a_clone_that_moved_since_rendering_is_recorded_as_lib_commit_with_a_warning(self):
        rendered = "0" * 40
        result, files = self.run_with(rendered)
        self.assertEqual(files["commit.txt"], rendered)
        self.assertEqual(files["lib_commit.txt"], head())
        self.assertIn(f"\nCommit      : {rendered}\n", result.stdout)
        self.assertIn("WARNING", result.stderr)
        self.assertIn(head(), result.stderr)

    def test_with_no_render_time_commit_the_clone_commit_at_job_start_is_recorded_with_a_warning(self):
        result, files = self.run_with("")
        self.assertEqual(files["commit.txt"], head())
        self.assertNotIn("lib_commit.txt", files)
        self.assertIn("WARNING", result.stderr)
        self.assertIn("edited is unknown", result.stderr)


@unittest.skipUnless(ON_KATANA, "needs Katana's module system")
class RecordCode(unittest.TestCase):
    """iris_record_code, which the script calls between writing run.py and
    running it, so a run.py Python cannot even parse leaves its diff."""

    def test_a_run_py_with_a_syntax_error_leaves_run_py_and_run_diff_and_fails_the_job(self):
        broken = (WORKFLOW / "src" / "run.py").read_text() + "def broken(:\n"
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp, "dataset", "runs", "1")
            script = Path(tmp, "run.py")
            script.write_text(broken)
            result = source_job_lib(sys.prefix, run_dir, commit=head(), then=(
                f'cp "{script}" "$RUN_DIR/run.py"\n'
                f'{record_step()}\n'
                'python "$RUN_DIR/run.py" --help'))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SyntaxError", result.stderr)
            self.assertEqual((run_dir / "run.py").read_text(), broken)
            self.assertIn("+def broken(:\n", (run_dir / "run.diff").read_text())
            self.assertIn("EDITED RUN", result.stdout)
            self.assertIn("+def broken(:\n", result.stdout)


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
