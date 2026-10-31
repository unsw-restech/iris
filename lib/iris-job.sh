# The run-time steps of every imaging-environment job, in one place.
#
# Source this from a job script after setting:
#   CODE     the workflow folder in the clone that served the form
#   ENV_DIR  the pinned imaging environment, /srv/.../envs/imaging/<n>
#   RUN_DIR  where this run's outputs go, <dataset>/runs/<job number>
# and optionally:
#   COMMIT   the clone's commit when the form rendered, which the code the
#            script embeds dates from (ADR-0006)
#
# It creates runs/, stops the job with one line if the environment is
# missing, then loads the Python module, activates the environment, puts
# lib/ on PYTHONPATH, exports CODE as IRIS_CODE for the entry script, which
# runs from the run directory, and creates the run directory. It then prints
# what the job runs with, the commit being COMMIT or else the clone's HEAD,
# and how to view the result. It defines iris_record_code, which the script
# calls once it has written run.py and before Python runs it, and iris_done,
# which the script calls after the run to print the view commands again.
# Nothing is installed.
# Keep it free of `set -u`: the module scripts reference unset variables.

: "${CODE:?set CODE before sourcing iris-job.sh}"
: "${ENV_DIR:?set ENV_DIR before sourcing iris-job.sh}"
: "${RUN_DIR:?set RUN_DIR before sourcing iris-job.sh}"

# The job's #PBS -o points at runs/, and PBS can only deliver the output,
# this script's errors included, to a folder that exists.
mkdir -p "$(dirname "$RUN_DIR")"

if [ ! -x "$ENV_DIR/bin/python" ]; then
    echo "ERROR: the IRIS imaging environment is missing at $ENV_DIR. Contact patrick.tung@unsw.edu.au." >&2
    exit 1
fi

. /etc/profile.d/modules.sh
module load python/3.13.2
. "$ENV_DIR/bin/activate"

IRIS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$IRIS_LIB${PYTHONPATH:+:$PYTHONPATH}"
export IRIS_CODE="$CODE"

mkdir -p "$RUN_DIR"

# The commands to view and compare runs: the short forms `module load iris`
# puts on the PATH when CODE is in the system clone (ADR-0003), else that
# clone's bin/ in full, so a dev run is viewed with the code that ran it.
IRIS_CLONE="$(cd "$CODE/../.." && pwd)"
if [ "$IRIS_CLONE" = /srv/scratch/katana_ai/iris/code ]; then
    IRIS_LOAD="module load iris" IRIS_VIEW=iris-view IRIS_COMPARE=iris-compare
else
    IRIS_LOAD="" IRIS_VIEW="$IRIS_CLONE/bin/iris-view" IRIS_COMPARE="$IRIS_CLONE/bin/iris-compare"
fi

# iris_view_lines <lead>: <lead>, then the commands to view this run and
# compare runs.
iris_view_lines() {
    echo "$1"
    [ -z "$IRIS_LOAD" ] || echo "$IRIS_LOAD"
    echo "$IRIS_VIEW $RUN_DIR"
    echo "and compare your runs with:"
    echo "$IRIS_COMPARE"
}

# iris_record_code <entry>: record the run's code in the run directory
# (iris.rundir, ADR-0006): the commit, COMMIT or else the clone's commit
# now, the clone's commit now as well if it has moved since the form
# rendered, as after a bin/syspull, and the diff of the run.py the script
# wrote against <entry> (src/run.py) in CODE at COMMIT, which it prints. It
# runs in a Python of its own, before the script's, so a run.py that cannot
# even start still leaves run.py and its diff. A record step: it only warns.
iris_record_code() {
    python -m iris.rundir "$RUN_DIR" "$CODE" "$1" "$COMMIT" ||
        echo "WARNING: could not record this run's code, so whether it is edited is unknown." >&2
}

# What the script calls once the run has finished.
iris_done() {
    echo ""
    iris_view_lines "Done. In a terminal in a Virtual Desktop, view the result with:"
}

echo "Job ID      : ${PBS_JOBID:-none}"
echo "Host        : $(hostname)"
echo "Code        : $CODE"
echo "Commit      : ${COMMIT:-$(git -C "$CODE" rev-parse HEAD 2> /dev/null)}"
echo "Environment : $ENV_DIR"
echo "Run dir     : $RUN_DIR"
if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi -L > /dev/null 2>&1; then
    echo "GPU         : $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
else
    echo "GPU         : none, running on CPU"
fi
echo ""
iris_view_lines "When this job has finished, in a terminal in a Virtual Desktop, view the result with:"
echo ""
