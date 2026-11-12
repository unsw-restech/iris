# Katana's constants, in one place: every script that can source bash
# takes them from here, the job library, the bin/iris-* tools, the Katana
# test jobs, bin/qwait, bin/syspull, bin/ocpull and bin/envpull among them.
# Sourcing it only sets them, so it is safe on the desktop too.
#
# Copies that must stay literal, the forms' Ruby test for the system clone,
# the modulefile's path and the form tests' paths, are compared with these
# by bin/check's "Katana constants" check. A form pins its environment
# version by name, which bin/check finds in the digest map below.
# shellcheck disable=SC2034  # used by the scripts that source it

# The system clone (Patrick, 2026-10-23; see AGENTS.md): the IRIS instance
# serves its workflows/ and `module load iris` its module/bin.
IRIS_SYSTEM_CLONE=/srv/scratch/katana_ai/iris/code
# The IRIS fork of OpenComposer's two checkouts, beside the system clone
# (ADR-0011, #170): the IRIS instance's, Katana OnDemand's OpenComposer
# system app, and the test instance's, a dev app each workflow author links
# in (ADR-0012), kept on one fork commit by bin/ocpull.
IRIS_INSTANCE_CHECKOUT=/srv/scratch/katana_ai/iris/OpenComposer-iris
IRIS_TEST_INSTANCE_CHECKOUT=/srv/scratch/katana_ai/iris/OpenComposer-iris-test
# Katana's Python module (../available-modules.md), for the job library's
# Katana test (lib/tests/katana/job_lib.pbs), which needs only the
# standard library. Workflows and the researcher tools run in containers.
IRIS_PYTHON_MODULE=python/3.13.2

# Environments as containers (ADR-0007, ADR-0008; envs/README.md). An
# environment version is <env>/<n>, <env> named after the lab it was first
# built for and <n> counting from 1: microct/1. The one exception is tools,
# the researcher tools' environment, which is no lab's (ADR-0010). A version's
# recipe is envs/<env>/<n>/, and its container is published to
# IRIS_ENV_REGISTRY tagged <env>-<n> (microct-1).
IRIS_ENV_REGISTRY=ghcr.io/unsw-restech/iris-env
# The IRIS environments folder in katana_ai scratch, a place chosen for it
# (ADR-0008, Patrick, 2026-11-06), not one Katana sets: version <env>/<n>'s
# container file is <folder>/<env>/<n>.sif (iris_env_file), with the
# digest it was pulled by in <folder>/<env>/<n>.digest beside it.
# bin/envpull fills it, through the data mover, with the versions live
# forms pin and the researcher tools' version (#125).
IRIS_ENVS_FOLDER=/srv/scratch/katana_ai/iris/envs
# The version the researcher tools (iris-view, iris-compare, the importer,
# rebuild) run in, whichever lab a run is from.
IRIS_TOOLS_ENV_VERSION=tools/1

# The digest map: every environment version and its container's digest in
# IRIS_ENV_REGISTRY, one "    [<env>/<n>]=<digest>" line each, so a script
# that can't source bash reads it with a regex. <digest> is sha256:<64 hex>,
# or "unpublished" until CI first publishes the version: CI builds every
# unpublished version and prints the line to put here instead
# (envs/README.md). A version's digest never changes once written.
declare -gA IRIS_ENV_DIGESTS=(
    [microct/1]=sha256:c1022d8514acbdb80dc038a72ac193699fb1a4b7a75fa1b2905c7b41fd04eb4f
    [tools/1]=sha256:02aec588cda0544f122b12a0ddeb6cd8e34a83724ed643b2712de46e4d3677ed
)

# The lab table: each lab, by its section id in index.html, and the
# environment version its new workflows start on, one "    [<lab>]=<env>/<n>"
# line each. Adding a lab is one line; labs may share an environment. A
# workflow already in a lab keeps the version its form pins.
declare -gA IRIS_LAB_ENVS=(
    [microct-lab]=microct/1
)

# iris_is_env_version <word>: whether <word> names an environment version,
# <env>/<n> with <n> counting from 1. iris_is_env_digest <word>: whether
# <word> is a digest map value, sha256:<64 hex> or unpublished.
# iris_form_pins <form>: the versions a form pins, one a line, from its
# "  IRIS_ENV_VERSION=<env>/<n>" lines. bin/envpull-dm.sh, which runs on
# the data mover and can't source this file, keeps its own copies of the
# first and last.
iris_is_env_version() { [[ "$1" =~ ^[a-z0-9-]+/[1-9][0-9]*$ ]]; }
iris_is_env_digest() { [[ "$1" =~ ^(sha256:[0-9a-f]{64}|unpublished)$ ]]; }
iris_form_pins() { tr -d '\r' < "$1" | sed -nE 's/^  IRIS_ENV_VERSION=(.*)$/\1/p'; }

# iris_env_file <env>/<n> [<folder>]: prints the version's container file
# in <folder>, IRIS_ENVS_FOLDER unless given.
iris_env_file() { echo "${2:-$IRIS_ENVS_FOLDER}/$1.sif"; }

# iris_env_ref <env>/<n>: prints the version's container by digest alone,
# <registry>@sha256:<hex>, the form Apptainer and docker pull; fails with
# one line on stderr if the version isn't in the digest map or is
# unpublished.
iris_env_ref() {
    local digest="${IRIS_ENV_DIGESTS[$1]-}"
    case "$digest" in
        sha256:*) echo "$IRIS_ENV_REGISTRY@$digest" ;;
        unpublished) echo "$1 is not published yet: its digest in lib/katana.sh is 'unpublished'" >&2; return 1 ;;
        *) echo "$1 is not in lib/katana.sh's digest map" >&2; return 1 ;;
    esac
}

# iris_in_system_clone <path>: whether <path>, a folder or file, is in the
# system clone, judged by its path alone, .. resolved, so it works for a
# path on Katana read from the desktop too.
iris_in_system_clone() {
    local path
    path="$(realpath -ms -- "$1")" || return 1
    [ "$path" = "$IRIS_SYSTEM_CLONE" ] || [[ "$path" == "$IRIS_SYSTEM_CLONE"/* ]]
}
