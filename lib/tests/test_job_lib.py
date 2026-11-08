"""Tests for lib/iris-job.sh, the run-time steps every imaging job sources.

Asserts only on what a job shows: its exit status, its output, the run
directory and, at the system boundary, the apptainer command it starts.
Each job starts with the header the reference form renders
(lib/tests/form_helper.rb, so Ruby is needed), its CODE the reference
workflow's folder in the clone that serves the form, its environment
version the one the form pins, and its environments folder one the test
makes.

The missing-container and start-line cases run anywhere, against a stand-in
apptainer that prints what it was asked to run. The cases that run a job in
a container need Apptainer and a real container file, so they run only on
Katana, in the stand-in container IRIS_STAND_IN names (lib/tests/katana/
stand-in.sh), which job_lib.pbs sets; bin/katana-test submits that job.
That job requests no GPUs, so it is also the CPU-only run.

    python3 -m unittest discover -s lib/tests
"""

import functools
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "lib"
WORKFLOW = REPO / "workflows" / "microct-2d-segmentation"
JOB_LIB = LIB / "iris-job.sh"
FORM_HELPER = LIB / "tests" / "form_helper.rb"
STAND_IN = os.environ.get("IRIS_STAND_IN", "")
GUIDE_HELP = "https://docs.restech.unsw.edu.au/iris/guide/#help"
DIGEST = "sha256:" + "ab" * 32
# What the job passes into the container, and nothing else (ADR-0008).
PASSED = {"PYTHONPATH", "IRIS_CODE", "USER", "PBS_JOBID", "PBS_QUEUE", "PYTHONUNBUFFERED",
          "IRIS_ENV_VERSION", "IRIS_ENV_DIGEST"}


def katana(name):
    return subprocess.run(
        ["bash", "-c", f'. "$1" && echo "${name}"', "-", str(LIB / "katana.sh")],
        capture_output=True, text=True, check=True).stdout.strip()


SYSTEM_CODE = Path(katana("IRIS_SYSTEM_CLONE"), "workflows", "microct-2d-segmentation")


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
def pinned_version():
    """The environment version the reference form pins."""
    script = rendered_script(WORKFLOW, "/srv/scratch/z0000000/dataset")
    return re.search(r"^IRIS_ENV_VERSION=(\S+)$", script, re.M).group(1)


@functools.cache
def rendered_lines(after):
    """The rendered script's line after the heredoc that writes run.py, the
    call recording the run's code, if `after` is 0; the container start
    line, joined with its continuation lines, if it is 1."""
    script = rendered_script(WORKFLOW, "/srv/scratch/z0000000/dataset")
    marker = re.search(r"<<'(\w+)'\n", script).group(1)
    lines = [line for line in script.split(f"\n{marker}\n", 1)[1].replace("\\\n", " ").splitlines() if line.strip()]
    return lines[after]


def envs_folder(tmp, container=None, digest=DIGEST):
    """An environments folder in `tmp` holding the pinned version's
    container file, a link to `container` (an empty file if None), and its
    digest file, holding `digest` unless that is None."""
    folder = Path(tmp, "envs")
    sif = folder / f"{pinned_version()}.sif"
    sif.parent.mkdir(parents=True)
    if container:
        sif.symlink_to(container)
    else:
        sif.touch()
    if digest is not None:
        sif.with_suffix(".digest").write_text(digest + "\n")
    return folder


def source_job_lib(envs, run_dir, then="echo AFTER", commit=None, code=WORKFLOW, view=None, env=None,
                   own_copy=False):
    """Run the rendered script's header, from #!/bin/bash to sourcing the
    library, for a run directory <dataset>/runs/<job>, then run `then`.
    The environments folder is `envs`; COMMIT, the clone's commit when the
    form rendered, is `commit` if given, and VIEW is `view` if given, as a
    workflow that writes no label volume sets it. `env` adds to the job's
    environment. The library sourced is this tree's lib/, whichever clone
    `code` is in, so these tests test the library rather than a
    workflow's copy of it; with `own_copy` it is the form's own source
    line, the workflow's copy (bin/libcopy)."""
    assert run_dir.parent.name == "runs", run_dir
    lines = rendered_script(code, run_dir.parent.parent).splitlines(keepends=True)
    end = next(i for i, line in enumerate(lines) if JOB_LIB.name in line)
    header = "".join(lines[:end])
    if commit is not None:
        header, n = re.subn(r"^COMMIT=.*$", lambda _: f'COMMIT="{commit}"', header, flags=re.M)
        assert n == 1, f"the rendered header sets COMMIT {n} times"
    header += f'ENVS_FOLDER="{envs}"\n'
    if view is not None:
        header += f'VIEW="{view}"\n'
    header += lines[end] if own_copy else f'source "{JOB_LIB}"\n'
    job_env = {k: v for k, v in os.environ.items()
               if k not in ("VIRTUAL_ENV", "PYTHONPATH", "CUDA_VISIBLE_DEVICES", "IRIS_HOME")}
    job_env.update({"PBS_JOBID": f"{run_dir.name}.kman.restech.unsw.edu.au", "PBS_QUEUE": "cpu",
                    "IRIS_TEST_HOST_ONLY": "leaked"})
    job_env.update(env or {})
    return subprocess.run(["bash", "-c", f"{header}{then}\n"], env=job_env, capture_output=True, text=True,
                          timeout=300)


class MissingContainer(unittest.TestCase):

    def test_stops_with_one_line_naming_the_version_its_file_and_the_guides_help(self):
        with tempfile.TemporaryDirectory() as tmp:
            envs = Path(tmp, "envs")
            run_dir = Path(tmp, "dataset", "runs", "1")
            result = source_job_lib(envs, run_dir)
            self.assertNotEqual(result.returncode, 0)
            lines = (result.stdout + result.stderr).strip().splitlines()
            self.assertEqual(len(lines), 1, lines)
            self.assertIn(pinned_version(), lines[0])
            self.assertIn(str(envs / f"{pinned_version()}.sif"), lines[0])
            self.assertIn(GUIDE_HELP, lines[0])
            self.assertFalse(run_dir.exists())
            # PBS delivers the job output to runs/, so it must exist even here.
            self.assertTrue(run_dir.parent.is_dir())


class StartLine(unittest.TestCase):
    """The apptainer command the job starts the record step and the entry
    script with, seen by a stand-in apptainer that prints each argument on
    a line of its own, then ENV, then the variables Apptainer would pass
    in, and runs nothing."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.envs = envs_folder(self.tmp.name)
        bin_dir = Path(self.tmp.name, "bin")
        bin_dir.mkdir()
        fake = bin_dir / "apptainer"
        fake.write_text('#!/bin/bash\nprintf "%s\\n" "$@" ENV\nenv | sed -n "s/^APPTAINERENV_//p" | sort\n')
        fake.chmod(0o755)
        self.path = f"{bin_dir}:{os.environ['PATH']}"
        self.n = 0

    def start(self, then=None, env=None, own_copy=False):
        """What the stand-in apptainer printed, as (arguments, variables)."""
        self.n += 1
        run_dir = Path(self.tmp.name, "dataset", "runs", str(self.n))
        result = source_job_lib(self.envs, run_dir, then=f"echo START\n{then or rendered_lines(1)}",
                                env={"PATH": self.path, **(env or {})}, own_copy=own_copy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args, variables = result.stdout.split("START\n", 1)[1].split("ENV\n", 1)
        return args.splitlines(), dict(line.split("=", 1) for line in variables.splitlines())

    def test_a_cpu_only_run_starts_the_container_clean_without_gpu_support(self):
        args, _ = self.start()
        sif = str(self.envs / f"{pinned_version()}.sif")
        self.assertEqual(args[:3], ["exec", "--cleanenv", sif])
        self.assertEqual(args[3:5], ["python", str(Path(self.tmp.name, "dataset", "runs", "1", "run.py"))])
        self.assertNotIn("--nv", args)

    def test_a_run_with_gpus_starts_the_container_with_gpu_support(self):
        args, variables = self.start(env={"CUDA_VISIBLE_DEVICES": "GPU-1234"})
        self.assertEqual(args[:3], ["exec", "--cleanenv", "--nv"])
        self.assertEqual(variables["CUDA_VISIBLE_DEVICES"], "GPU-1234")

    def test_only_what_the_run_needs_is_passed_in(self):
        _, variables = self.start()
        self.assertEqual(set(variables), PASSED)
        self.assertEqual(variables["PYTHONPATH"], str(LIB))
        self.assertEqual(variables["IRIS_CODE"], str(WORKFLOW))
        self.assertEqual(variables["USER"], os.environ["USER"])
        self.assertEqual(variables["PBS_JOBID"], "1.kman.restech.unsw.edu.au")
        self.assertEqual(variables["PBS_QUEUE"], "cpu")
        self.assertEqual(variables["PYTHONUNBUFFERED"], "1")

    def test_a_job_as_the_form_renders_it_runs_the_workflows_own_copy_of_the_library(self):
        _, variables = self.start(own_copy=True)
        self.assertEqual(variables["PYTHONPATH"], str(WORKFLOW / "lib"))
        self.assertEqual(variables["IRIS_CODE"], str(WORKFLOW))

    def test_iris_home_is_passed_in_when_it_is_set(self):
        _, variables = self.start(env={"IRIS_HOME": "/srv/scratch/z0000000/elsewhere"})
        self.assertEqual(set(variables), PASSED | {"IRIS_HOME"})
        self.assertEqual(variables["IRIS_HOME"], "/srv/scratch/z0000000/elsewhere")

    def test_the_run_gets_the_pinned_version_and_the_digest_beside_its_file(self):
        _, variables = self.start()
        self.assertEqual(variables["IRIS_ENV_VERSION"], pinned_version())
        self.assertEqual(variables["IRIS_ENV_DIGEST"], DIGEST)

    def test_the_code_recorder_runs_in_the_container_too(self):
        args, _ = self.start(then=rendered_lines(0))
        self.assertEqual(args[2:6], [str(self.envs / f"{pinned_version()}.sif"), "python", "-m", "iris.rundir"])

    def test_the_header_names_the_version_and_its_digest(self):
        run_dir = Path(self.tmp.name, "dataset", "runs", "9")
        result = source_job_lib(self.envs, run_dir)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"\nEnvironment : {pinned_version()} ({DIGEST})\n", result.stdout)
        self.assertIn(f"\nRun dir     : {run_dir}\n", result.stdout)


@unittest.skipUnless(STAND_IN, "needs Katana's Apptainer and the stand-in container (lib/tests/katana/stand-in.sh)")
class InTheContainer(unittest.TestCase):
    """A job in the stand-in container, with no GPUs: the CPU-only run."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.envs = envs_folder(cls.tmp.name, STAND_IN)
        cls.run_dir = Path(cls.tmp.name, "dataset", "runs", "1234")
        cls.result = source_job_lib(cls.envs, cls.run_dir, then=(
            'iris_container python -c "import os, sys, iris.rundir; '
            "print('PYTHON', sys.executable); print('LIB', iris.rundir.__file__); "
            "print('OS', open('/etc/os-release').readline().strip()); "
            "print('VARS', ' '.join(sorted(os.environ)))\""))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def line(self, key):
        return next(line.split(" ", 1)[1] for line in self.result.stdout.splitlines() if line.startswith(key + " "))

    def test_succeeds(self):
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)

    def test_python_is_the_containers_with_lib_on_its_path(self):
        self.assertEqual(self.line("OS"), 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"')
        self.assertEqual(self.line("PYTHON"), "/usr/local/bin/python")
        self.assertEqual(self.line("LIB"), str(LIB / "iris" / "rundir.py"))

    def test_the_hosts_variables_stay_out(self):
        variables = set(self.line("VARS").split())
        self.assertLessEqual(PASSED, variables)
        self.assertNotIn("IRIS_TEST_HOST_ONLY", variables)
        self.assertNotIn("LOADEDMODULES", variables)

    def test_a_cpu_only_job_gets_no_cuda_devices(self):
        self.assertNotIn("CUDA_VISIBLE_DEVICES", self.line("VARS").split())

    def test_the_header_shows_the_clones_commit_the_environment_and_the_run_directory(self):
        self.assertIn(f"\nCommit      : {head()}\n", self.result.stdout)
        self.assertIn(f"\nEnvironment : {pinned_version()} ({DIGEST})\n", self.result.stdout)
        self.assertIn(f"\nRun dir     : {self.run_dir}\n", self.result.stdout)

    def test_records_no_code_before_the_script_calls_iris_record_code(self):
        self.assertEqual(list(self.run_dir.iterdir()), [])

    def test_the_entry_script_finds_the_workflow_folder(self):
        result = source_job_lib(self.envs, self.run_dir.with_name("1235"),
                                then="iris_container python -c \"import os; print('IRIS_CODE=' + os.environ['IRIS_CODE'])\"")
        self.assertIn(f"IRIS_CODE={WORKFLOW}\n", result.stdout)


@unittest.skipUnless(STAND_IN, "needs Katana's Apptainer and the stand-in container (lib/tests/katana/stand-in.sh)")
class RenderTimeCommit(unittest.TestCase):
    """The embedded code dates from when the form rendered, lib/ from when
    the job starts (ADR-0006): iris_record_code records both."""

    def run_with(self, commit):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp, "dataset", "runs", "1")
            result = source_job_lib(envs_folder(tmp, STAND_IN), run_dir, commit=commit, then=(
                f'cp "{WORKFLOW / "src" / "run.py"}" "$RUN_DIR/run.py"\n'
                f'{rendered_lines(0)}'))
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


@unittest.skipUnless(STAND_IN, "needs Katana's Apptainer and the stand-in container (lib/tests/katana/stand-in.sh)")
class RecordCode(unittest.TestCase):
    """iris_record_code, which the script calls between writing run.py and
    running it, so a run.py Python cannot even parse leaves its diff: the
    code a researcher edits in the pane is what runs (ADR-0006)."""

    def test_a_run_py_with_a_syntax_error_leaves_run_py_and_run_diff_and_fails_the_job(self):
        broken = (WORKFLOW / "src" / "run.py").read_text() + "def broken(:\n"
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp, "dataset", "runs", "1")
            script = Path(tmp, "run.py")
            script.write_text(broken)
            result = source_job_lib(envs_folder(tmp, STAND_IN), run_dir, commit=head(), then=(
                f'cp "{script}" "$RUN_DIR/run.py"\n'
                f'{rendered_lines(0)}\n'
                f'{rendered_lines(1).split(" --", 1)[0]} --help'))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SyntaxError", result.stderr)
            self.assertEqual((run_dir / "run.py").read_text(), broken)
            self.assertIn("+def broken(:\n", (run_dir / "run.diff").read_text())
            self.assertIn("EDITED RUN", result.stdout)
            self.assertIn("+def broken(:\n", result.stdout)


class ViewLines(unittest.TestCase):
    """The iris-view and iris-compare lines the job prints before and after
    training: the short forms `module load iris` gives from the system
    clone (ADR-0003), that clone's bin/ in full from any other."""

    def output(self, code, view=None):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp, "dataset", "runs", "1")
            result = source_job_lib(envs_folder(tmp), run_dir, code=code, then="echo TRAINING; iris_done", view=view)
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

    def test_a_workflow_that_writes_no_label_volume_prints_only_how_to_compare_runs(self):
        before, after, run_dir = self.output(WORKFLOW, view="no")
        for part in (before, after):
            self.assertNotIn("iris-view", part)
            self.assertIn(f"compare your runs with:\n{REPO}/bin/iris-compare\n", part)
        self.assertTrue(after.startswith("\nDone. "), after)

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
