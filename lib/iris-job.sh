# The run-time steps of every imaging job, in one place.
#
# Source this from a job script after setting:
#   CODE              the workflow folder in the clone that served the form
#   IRIS_ENV_VERSION  the environment version the form pins, <env>/<n>
#                     (envs/README.md)
#   RUN_DIR           where this run's outputs go, <dataset>/runs/<job number>
# and optionally:
#   COMMIT       the clone's commit when the form rendered, which the code
#                the script embeds dates from (ADR-0006)
#   VIEW         "no" if the workflow writes no label volume, so the job
#                prints how to compare runs but no iris-view line
#   ENVS_FOLDER  the environments folder, lib/katana.sh's IRIS_ENVS_FOLDER
#                unless set; the library's tests point it at a stand-in
#
# It creates runs/, stops the job with one line if the pinned version's
# container file, <folder>/<env>/<n>.sif, is missing, then exports
# IRIS_ENV_VERSION and IRIS_ENV_DIGEST, the digest in <n>.digest beside the
# file, for the run record, and creates the run directory. It then prints
# what the job runs with, the commit being COMMIT or else the clone's HEAD,
# and how to view the result. It defines iris_container, which runs a
# command in the container; iris_record_code, which the script calls once
# it has written run.py and before Python runs it; and iris_done, which the
# script calls after the run to print the view commands again. Nothing is
# installed, and no module is loaded.

: "${CODE:?set CODE before sourcing iris-job.sh}"
: "${IRIS_ENV_VERSION:?set IRIS_ENV_VERSION before sourcing iris-job.sh}"
: "${RUN_DIR:?set RUN_DIR before sourcing iris-job.sh}"

# The job's #PBS -o points at runs/, and PBS can only deliver the output,
# this script's errors included, to a folder that exists.
mkdir -p "$(dirname "$RUN_DIR")"

IRIS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$IRIS_LIB/katana.sh"

IRIS_ENV_SIF="${ENVS_FOLDER:-$IRIS_ENVS_FOLDER}/$IRIS_ENV_VERSION.sif"
if [ ! -f "$IRIS_ENV_SIF" ]; then
    echo "ERROR: the IRIS environment $IRIS_ENV_VERSION is missing: there is no container file at $IRIS_ENV_SIF. For help, see https://docs.restech.unsw.edu.au/iris/guide/#help" >&2
    exit 1
fi
IRIS_ENV_DIGEST="$(head -n 1 "${IRIS_ENV_SIF%.sif}.digest" 2> /dev/null)"
export IRIS_ENV_VERSION IRIS_ENV_DIGEST

mkdir -p "$RUN_DIR"

# iris_container <command>...: runs <command> in the pinned container, with
# the GPU (--nv) when PBS gave the job any, which it says by setting
# CUDA_VISIBLE_DEVICES, and without for a CPU-only run (0 GPUs), where --nv
# would fail on missing drivers. --cleanenv keeps the job's modules and
# host libraries out; only what the run needs is passed in, through
# Apptainer's APPTAINERENV_ variables, which no value can break as a comma
# breaks --env: lib/ on the Python path, the workflow folder as IRIS_CODE
# for the entry script, IRIS_HOME if set, USER, the PBS job ID and queue,
# unbuffered Python output, the environment version and digest, and
# CUDA_VISIBLE_DEVICES if PBS set it. Katana binds /srv and home, so the
# clone, the dataset and the run directory are all in the container.
iris_container() {
    local v strip=() gpu=() pass=(
        "APPTAINERENV_PYTHONPATH=$IRIS_LIB"
        "APPTAINERENV_IRIS_CODE=$CODE"
        "APPTAINERENV_USER=$USER"
        "APPTAINERENV_PBS_JOBID=$PBS_JOBID"
        "APPTAINERENV_PBS_QUEUE=$PBS_QUEUE"
        "APPTAINERENV_PYTHONUNBUFFERED=1"
        "APPTAINERENV_IRIS_ENV_VERSION=$IRIS_ENV_VERSION"
        "APPTAINERENV_IRIS_ENV_DIGEST=$IRIS_ENV_DIGEST"
    )
    for v in $(compgen -v APPTAINERENV_) $(compgen -v SINGULARITYENV_); do strip+=(-u "$v"); done
    [ -z "$IRIS_HOME" ] || pass+=("APPTAINERENV_IRIS_HOME=$IRIS_HOME")
    if [ -n "$CUDA_VISIBLE_DEVICES" ]; then
        gpu=(--nv)
        pass+=("APPTAINERENV_CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES")
    fi
    env "${strip[@]}" "${pass[@]}" apptainer exec --cleanenv "${gpu[@]}" "$IRIS_ENV_SIF" "$@"
}

# The commands to view and compare runs: the short forms `module load iris`
# puts on the PATH when CODE is in the system clone (ADR-0003), else that
# clone's bin/ in full, so a dev run is viewed with the code that ran it.
IRIS_CLONE="$(cd "$CODE/../.." && pwd)"
if iris_in_system_clone "$CODE"; then
    IRIS_LOAD="module load iris" IRIS_VIEW=iris-view IRIS_COMPARE=iris-compare
else
    IRIS_LOAD="" IRIS_VIEW="$IRIS_CLONE/bin/iris-view" IRIS_COMPARE="$IRIS_CLONE/bin/iris-compare"
fi

# iris_view_lines <lead>: <lead>, then the commands to view this run and
# compare runs, or with VIEW=no only to compare them, as a workflow that
# writes no label volume has nothing for iris-view to show.
iris_view_lines() {
    if [ "$VIEW" = no ]; then
        echo "$1 compare your runs with:"
        [ -z "$IRIS_LOAD" ] || echo "$IRIS_LOAD"
    else
        echo "$1 view the result with:"
        [ -z "$IRIS_LOAD" ] || echo "$IRIS_LOAD"
        echo "$IRIS_VIEW $RUN_DIR"
        echo "and compare your runs with:"
    fi
    echo "$IRIS_COMPARE"
}

# iris_record_code <entry>: record the run's code in the run directory
# (iris.rundir, ADR-0006): the commit, COMMIT or else the clone's commit
# now, the clone's commit now as well if it has moved since the form
# rendered, as after a bin/syspull, and the diff of the run.py the script
# wrote against <entry> (src/run.py) in CODE at COMMIT, which it prints. It
# runs in a Python of its own, the container's, before the script's, so a
# run.py that cannot even start still leaves run.py and its diff, and the
# record step uses the same software as the run. A record step: it only
# warns.
iris_record_code() {
    iris_container python -m iris.rundir "$RUN_DIR" "$CODE" "$1" "$COMMIT" ||
        echo "WARNING: could not record this run's code, so whether it is edited is unknown." >&2
}

# What the script calls once the run has finished.
iris_done() {
    echo ""
    iris_view_lines "Done. In a terminal in a Virtual Desktop,"
}

echo "Job ID      : ${PBS_JOBID:-none}"
echo "Host        : $(hostname)"
echo "Code        : $CODE"
echo "Commit      : ${COMMIT:-$(git -C "$CODE" rev-parse HEAD 2> /dev/null)}"
echo "Environment : $IRIS_ENV_VERSION (${IRIS_ENV_DIGEST:-digest unknown: no ${IRIS_ENV_SIF%.sif}.digest})"
echo "Container   : $IRIS_ENV_SIF"
echo "Run dir     : $RUN_DIR"
if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi -L > /dev/null 2>&1; then
    echo "GPU         : $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
else
    echo "GPU         : none, running on CPU"
fi
echo ""
iris_view_lines "When this job has finished, in a terminal in a Virtual Desktop,"
echo ""
