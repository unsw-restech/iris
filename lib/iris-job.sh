# The run-time steps of every imaging-environment job, in one place.
#
# Source this from a job script after setting:
#   CODE     the workflow folder in the clone that served the form
#   ENV_DIR  the pinned imaging environment, /srv/.../envs/imaging/<n>
#   RUN_DIR  where this run's outputs go, <dataset>/runs/<job number>
#
# It creates runs/, stops the job with one line if the environment is
# missing, then loads the Python module, activates the environment, puts
# lib/ on PYTHONPATH, creates the run directory, records the clone's commit
# in it and prints the iris-view and iris-compare lines, with the full path of
# this clone's bin/ in IRIS_BIN, since researchers run them from the clone
# that served the form. Nothing is installed. Keep it free of `set -u`: the
# module scripts reference unset variables.

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
IRIS_BIN="$(cd "$IRIS_LIB/../bin" && pwd)"
export PYTHONPATH="$IRIS_LIB${PYTHONPATH:+:$PYTHONPATH}"

mkdir -p "$RUN_DIR"
git -C "$CODE" rev-parse HEAD > "$RUN_DIR/commit.txt"

echo "Job ID      : ${PBS_JOBID:-none}"
echo "Host        : $(hostname)"
echo "Code        : $CODE"
echo "Commit      : $(cat "$RUN_DIR/commit.txt")"
echo "Environment : $ENV_DIR"
echo "Run dir     : $RUN_DIR"
if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi -L > /dev/null 2>&1; then
    echo "GPU         : $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
else
    echo "GPU         : none, running on CPU"
fi
echo ""
echo "When this job has finished, in a terminal in a Virtual Desktop, view the result with:"
echo "$IRIS_BIN/iris-view $RUN_DIR"
echo "and compare your runs with:"
echo "$IRIS_BIN/iris-compare"
echo ""
