# Katana's constants, in one place: every script that can source bash
# takes them from here, the job library, the bin/iris-* tools, the Katana
# test jobs, bin/qwait and bin/syspull among them. Sourcing it only sets
# them, so it is safe on the desktop too.
#
# Copies that must stay literal, the imaging forms' pane ENV_DIR
# (ADR-0006), the forms' Ruby test for the system clone, the modulefile's
# path and the form tests' paths, are compared with these by bin/check's
# "Katana constants" check. Moving to imaging environment 2 is the one line
# here and those copies, which that check lists.
# shellcheck disable=SC2034  # used by the scripts that source it

# The system clone (Patrick, 2026-10-23; see AGENTS.md): the system
# OpenComposer serves its workflows/ and `module load iris` its module/bin.
IRIS_SYSTEM_CLONE=/srv/scratch/katana_ai/iris/code
# The imaging environment the imaging forms pin (envs/imaging/).
IRIS_ENV_DIR=/srv/scratch/katana_ai/iris/envs/imaging/1
# The Python module that environment was built on (../available-modules.md).
IRIS_PYTHON_MODULE=python/3.13.2

# iris_in_system_clone <path>: whether <path>, a folder or file, is in the
# system clone, judged by its path alone, .. resolved, so it works for a
# path on Katana read from the desktop too.
iris_in_system_clone() {
    local path
    path="$(realpath -ms -- "$1")" || return 1
    [ "$path" = "$IRIS_SYSTEM_CLONE" ] || [[ "$path" == "$IRIS_SYSTEM_CLONE"/* ]]
}
