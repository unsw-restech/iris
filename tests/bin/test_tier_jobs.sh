#!/bin/bash
# bin/check's "Run and verified workflows cite a job" check against
# throwaway site trees. Prints each failed case and nothing on success, so
# bin/check can run it.
#
#   tests/bin/test_tier_jobs.sh
#
# bin/check name: tier jobs test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="Run and verified workflows cite a job"
workflows=(seg:ct-lab:active hello:ct-lab:active tumour:mr-lab:planned)

site_tree "$scratch/clean" "${workflows[@]}"
expect pass "$scratch/clean" "$name"

# The tier row names hello, but no line cites a job for it.
site_tree "$scratch/no-job" "${workflows[@]}"
sed -i '/^`hello` ran/d' "$scratch/no-job/CONTRIBUTING.md"
expect fail "$scratch/no-job" "$name"

# A backtick between the slug and the job breaks the citation.
site_tree "$scratch/backtick-between" "${workflows[@]}"
sed -i 's/^`hello` ran from the system OnDemand/`hello` ran from `\/pun\/sys\/`/' "$scratch/backtick-between/CONTRIBUTING.md"
expect fail "$scratch/backtick-between" "$name"

# The tier row itself doesn't count as a citation.
site_tree "$scratch/only-in-the-row" "${workflows[@]}"
sed -i '/^`hello` ran/d; s/^\(| \*\*Run and verified\*\* | .*\) | Page |$/\1 | Page, (job 1001) |/' "$scratch/only-in-the-row/CONTRIBUTING.md"
expect fail "$scratch/only-in-the-row" "$name"

# A planned workflow needs no job.
site_tree "$scratch/planned-only" tumour:mr-lab:planned
expect pass "$scratch/planned-only" "$name"
