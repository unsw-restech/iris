"""The entry script as the form's job runs it: a copy written into the run
directory, run from there with IRIS_CODE naming the workflow folder in the
clone, as lib/iris-job.sh exports it (ADR-0006). Runs in the desktop CPU
venv, like test_synthetic.
"""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_synthetic import ENTRY, WORKFLOW, entry_command, make_volume, two_class_labels, write_dataset


class RunFromRunDirectory(unittest.TestCase):

    def test_records_the_workflow_it_came_from(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp, "dataset")
            write_dataset(dataset, make_volume(), two_class_labels())
            run_dir = dataset / "runs" / "1234"
            run_dir.mkdir(parents=True)
            shutil.copy(ENTRY, run_dir / "run.py")
            cmd, env = entry_command(dataset, run_dir, Path(tmp, "iris"))
            cmd[1] = str(run_dir / "run.py")
            env["IRIS_CODE"] = str(WORKFLOW)
            result = subprocess.run(cmd, env=env, cwd=tmp, capture_output=True, text=True, timeout=600)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            tags = json.loads((run_dir / "run.json").read_text())["tags"]
            self.assertEqual(tags["slug"], "microct-2d-segmentation")
            self.assertEqual(Path(tags["run_dir"]), run_dir)


if __name__ == "__main__":
    unittest.main()
