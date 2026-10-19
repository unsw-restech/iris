"""iris-compare: import new runs, then open the tracking store in MLflow.

Run in a Virtual Desktop. It runs the importer first, so every finished run
is in the store (jobs never write it: docs/adr/0001). If another import
holds the store, it says so and shows what is already there. It then serves
the store with `mlflow ui` on 127.0.0.1 only, so no port is open to anyone
else, and opens Firefox at it. Ctrl+C stops the server.

    python -m iris.compare        # or bin/iris-compare
"""

import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

os.environ.setdefault("MLFLOW_DISABLE_AGENT_HINT", "1")

from iris.record import iris_home  # noqa: E402
from iris.tracking import artifact_root, import_runs, store_uri, summary  # noqa: E402

HOST = "127.0.0.1"
START_TIMEOUT = 120  # seconds; a first start on GPFS takes a while


def free_port():
    with socket.socket() as s:
        s.bind((HOST, 0))
        return s.getsockname()[1]


def start_ui(home=None):
    """Serve the tracking store in `home` with `mlflow ui` on localhost.
    Returns the server process and its URL once it answers; its log is
    ui.log next to the store."""
    home = home or iris_home()
    port = free_port()
    url = f"http://{HOST}:{port}"
    with open(home / "ui.log", "w") as log:
        server = subprocess.Popen(
            [sys.executable, "-m", "mlflow", "ui",
             "--backend-store-uri", store_uri(home),
             "--default-artifact-root", artifact_root(home), "--no-serve-artifacts",
             "--host", HOST, "--port", str(port), "--workers", "1"],
            stdout=log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + START_TIMEOUT
    while time.monotonic() < deadline:
        if server.poll() is not None:
            raise RuntimeError(f"mlflow ui stopped at start-up; see {home / 'ui.log'}")
        try:
            with urllib.request.urlopen(url + "/health", timeout=2):
                return server, url
        except OSError:
            time.sleep(0.5)
    server.terminate()
    raise RuntimeError(f"mlflow ui did not answer within {START_TIMEOUT} s; see {home / 'ui.log'}")


def main():
    home = iris_home()
    result = import_runs(home, wait=False)
    if result is None:
        print("Another import into this store is running, so new runs may be missing:"
              " showing the runs already imported.")
    else:
        print(summary(result, home))
    if not (home / "tracking.db").exists():
        sys.exit(f"There is no tracking store at {home / 'tracking.db'} yet.")

    server, url = start_ui(home)
    print(f"MLflow is at {url}. Leave this open while you use it; Ctrl+C stops it.")
    firefox = shutil.which("firefox")
    if firefox:
        subprocess.Popen([firefox, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        print(f"Firefox was not found: open {url} in a browser in this desktop.")
    try:
        server.wait()
    except KeyboardInterrupt:
        server.terminate()
        server.wait()


if __name__ == "__main__":
    main()
