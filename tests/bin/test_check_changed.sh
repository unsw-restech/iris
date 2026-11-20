#!/bin/bash
# bin/check-changed, which picks bin/check --changed's checks, in a
# throwaway repo with its own origin/main, then bin/check --changed itself
# in a scratch site tree: the tests it runs, shellcheck on changed scripts
# only, every rule over the tree, a check name it lacks, and no pass
# recorded for .githooks/pre-push.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_check_changed.sh
#
# bin/check name: check-changed test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

repo="$scratch/repo"
mkdir -p "$repo/bin" "$repo/tests/bin" "$repo/lib" "$repo/.github/workflows" "$repo/_archive/old" "$repo/envs/tools/1"
cp bin/check-changed bin/check-passed bin/tracked-tree "$repo/bin/"
printf '#!/bin/bash\necho run\n' > "$repo/bin/run"
printf '#!/bin/bash\necho run-more\n' > "$repo/bin/run-more"
echo 'name: ci' > "$repo/.github/workflows/ci.yml"
echo 'x = 1' > "$repo/lib/tool.py"
echo 'notes' > "$repo/notes.md"
echo 'old' > "$repo/_archive/old/form.sh"
echo 'a dot' > "$repo/lib/a.b"
echo 'gone soon' > "$repo/bin/gone"
echo 'pkg==1' > "$repo/envs/tools/1/requirements.lock"
# test_run.sh names bin/run; test_more.sh names bin/run-more, which holds
# bin/run inside it; test_other.sh names bin/run only on its name line.
printf '#!/bin/bash\n# bin/check name: run test\nbin/run\n' > "$repo/tests/bin/test_run.sh"
printf '#!/bin/bash\n"$repo"/bin/run-more\n' > "$repo/tests/bin/test_more.sh"
printf '#!/bin/bash\n# bin/check name: bin/run\ntrue\n' > "$repo/tests/bin/test_other.sh"
# test_dot.sh names lib/aXb, which lib/a.b matches only as a regex; test_gone.sh
# names bin/gone, to be deleted.
printf '#!/bin/bash\nlib/aXb\n' > "$repo/tests/bin/test_dot.sh"
printf '#!/bin/bash\nbin/gone\n' > "$repo/tests/bin/test_gone.sh"
git -C "$repo" init -q -b main
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m fixture
git -C "$repo" update-ref refs/remotes/origin/main HEAD

fail() { echo "check-changed $1"; }
# listed: runs bin/check-changed in the repo, its output to $out.
listed() { out="$("$repo/bin/check-changed")"; code=$?; }
has() { grep -qxF "$(printf '%s\t%s' "$1" "$2")" <<< "$out" || fail "$case: no line '$1 $2'"; }
lacks() { ! grep -qxF "$(printf '%s\t%s' "$1" "$2")" <<< "$out" || fail "$case: a line '$1 $2'"; }

case="nothing changed"
listed
[ "$code" = 1 ] || fail "$case: exit $code, not 1"

case="an edited script"
echo '# more' >> "$repo/bin/run"
listed
[ "$code" = 0 ] || fail "$case: exit $code"
has file bin/run
has test tests/bin/test_run.sh
lacks check shellcheck
lacks test tests/bin/test_more.sh
lacks test tests/bin/test_other.sh
lacks untested bin/run
lacks check actionlint
git -C "$repo" checkout -q -- bin/run

case="an untracked file and a workflow"
echo 'new' > "$repo/new.md"
echo '# more' >> "$repo/.github/workflows/ci.yml"
listed
[ "$code" = 0 ] || fail "$case: exit $code"
has file new.md
has untested new.md
has check actionlint
lacks check shellcheck
rm "$repo/new.md"; git -C "$repo" checkout -q -- .github/workflows/ci.yml

case="a Python file and a changed test"
echo 'y = 2' >> "$repo/lib/tool.py"
echo '# more' >> "$repo/tests/bin/test_other.sh"
listed
has check ruff
has check "synthetic-dataset test"
has test tests/bin/test_other.sh
lacks untested tests/bin/test_other.sh
git -C "$repo" checkout -q -- lib/tool.py tests/bin/test_other.sh

case="a dotted path, a deleted file and an environment"
echo '# more' >> "$repo/lib/a.b"
rm "$repo/bin/gone"
echo 'pkg==2' > "$repo/envs/tools/1/requirements.lock"
listed
has untested lib/a.b
lacks test tests/bin/test_dot.sh
has file bin/gone
has test tests/bin/test_gone.sh
has check "environment versions match the digest map"
has check "synthetic-dataset test"
git -C "$repo" checkout -q -- lib/a.b bin/gone envs

case="a committed change on a branch"
echo '# more' >> "$repo/bin/run-more"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q -am more
listed
has test tests/bin/test_more.sh
lacks test tests/bin/test_run.sh
# Given HEAD as the base, the commit is no change.
"$repo/bin/check-changed" HEAD > /dev/null
code=$?
[ "$code" = 1 ] || fail "a base given: exit $code, not 1"
git -C "$repo" reset -q --hard origin/main

# A recorded full pass nearest HEAD is the base (bin/check-passed --last):
# only what changed since it is listed.
passed="$repo/.git/iris/check-passed"
# record_pass: records the working tree as a full pass on HEAD, as a
# passing bin/check does.
record_pass() { (cd "$repo" && bin/check-passed --record "$(bin/tracked-tree)"); }

case="no pass recorded"
echo '# more' >> "$repo/bin/run"
listed
has base "the merge-base with origin/main"
git -C "$repo" checkout -q -- bin/run

case="a pass on the branch"
echo '# more' >> "$repo/bin/run-more"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q -am more
record_pass
echo '# more' >> "$repo/bin/run"
listed
has base "the full pass on $(git -C "$repo" rev-parse --short HEAD)"
has test tests/bin/test_run.sh
lacks test tests/bin/test_more.sh
lacks file bin/run-more
git -C "$repo" checkout -q -- bin/run

case="nothing changed since the pass"
listed
[ "$code" = 1 ] || fail "$case: exit $code, not 1"
has base "the full pass on $(git -C "$repo" rev-parse --short HEAD)"

case="a pass that saw an edit since undone"
echo '# edit' >> "$repo/bin/run"
record_pass
git -C "$repo" checkout -q -- bin/run
listed
has file bin/run
lacks file bin/run-more

case="a given base over a pass"
"$repo/bin/check-changed" origin/main > "$scratch/given"
grep -qxF "$(printf 'base\torigin/main')" "$scratch/given" || fail "$case: no line 'base origin/main'"
grep -qxF "$(printf 'file\tbin/run-more')" "$scratch/given" || fail "$case: bin/run-more not listed"

case="a pass off the branch"
git -C "$repo" switch -q -c other origin/main
echo '# other' >> "$repo/notes.md"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q -am other
record_pass
git -C "$repo" switch -q main
git -C "$repo" branch -q -D other
echo '# more' >> "$repo/bin/run"
listed
# The newest record is other's, not on main, so main's earlier pass is used.
has base "the full pass on $(git -C "$repo" rev-parse --short HEAD)"
lacks file notes.md
git -C "$repo" checkout -q -- bin/run

# A pass recorded later on an older commit, as a main clone records one on
# the main a branch then merges: the pass nearest HEAD is still the base.
case="a newer pass further back"
git -C "$repo" switch -q --detach origin/main
record_pass
git -C "$repo" switch -q main
echo '# more' >> "$repo/bin/run"
listed
has base "the full pass on $(git -C "$repo" rev-parse --short HEAD)"
lacks file bin/run-more
git -C "$repo" checkout -q -- bin/run

# A record written by hand, since git keeps every tree a test can make.
case="a pass whose tree git no longer holds"
: > "$passed"
echo "0123456789abcdef0123456789abcdef01234567 2026-01-01T00:00:00Z $(git -C "$repo" rev-parse --short HEAD)" >> "$passed"
echo '# more' >> "$repo/bin/run"
listed
has base "the merge-base with origin/main"
has file bin/run-more
git -C "$repo" checkout -q -- bin/run
rm -f "$passed"
git -C "$repo" reset -q --hard origin/main

case="an archived script"
echo '# more' >> "$repo/_archive/old/form.sh"
listed
has file _archive/old/form.sh
lacks check shellcheck
git -C "$repo" checkout -q -- _archive

case="a base that doesn't resolve"
"$repo/bin/check-changed" no-such-commit 2> /dev/null
code=$?
[ "$code" = 2 ] || fail "$case: exit $code, not 2"

# bin/check --changed in a clone of this one, its working tree's edits and
# untracked files copied in, so it passes every rule over the tree as
# --changed runs them all (the library copies' rule reads its history).
# Its tests/bin tests are swapped for two: test_notes.sh names notes.md and
# fails unless it reads "pass"; test_boom.sh always fails and names nothing
# changed. A fake uvx stands in for shellcheck, flagging each script it is
# given, so the run shows which files it checked.
site="$scratch/site"
mkdir -p "$scratch/path"
git clone -q --shared . "$site"
{ git diff -z --name-only --diff-filter=d HEAD; git ls-files -z --others --exclude-standard; } |
    tar --null -T - -cf - | tar -xf - -C "$site"
git diff -z --name-only --diff-filter=D HEAD | (cd "$site" && xargs -0 -r rm -f --)
rm "$site"/tests/bin/test_*.sh
printf '#!/bin/bash\n# bin/check name: notes test\ngrep -q pass notes.md || echo "notes.md: no pass"\n' > "$site/tests/bin/test_notes.sh"
printf '#!/bin/bash\n# bin/check name: boom test\necho boom\n' > "$site/tests/bin/test_boom.sh"
printf '#!/bin/bash\necho old\n' > "$site/bin/old-tool"
echo 'start' > "$site/notes.md"
printf '#!/bin/bash\ncat > /dev/null\necho "-:1:1: checked"\n' > "$scratch/path/uvx"
chmod +x "$scratch/path/uvx" "$site/bin/old-tool" "$site"/tests/bin/test_*.sh
git -C "$site" add -A
git -C "$site" -c user.name=t -c user.email=t@t commit -q -m fixture
git -C "$site" update-ref refs/remotes/origin/main HEAD
# Unset GITHUB_EVENT_NAME, so in a pull request's CI run bin/run-proof
# --check doesn't take the fixture for that pull request.
changed() { out="$(cd "$site" && env -u GITHUB_EVENT_NAME PATH="$scratch/path:$PATH" bin/check --changed 2>&1)"; code=$?; }
ran_fail() { grep -qxF "FAIL: $1" <<< "$out" || fail "--changed $case: no FAIL: $1"; }
no_fail() { ! grep -qxF "FAIL: $1" <<< "$out" || fail "--changed $case: FAIL: $1"; }

case="nothing changed"
changed
[ "$code" = 2 ] || fail "--changed $case: exit $code, not 2"

case="a failing test and a new script"
printf '#!/bin/bash\necho new\n' > "$site/bin/new-tool"
echo 'fail' > "$site/notes.md"
changed
[ "$code" = 1 ] || fail "--changed $case: exit $code, not 1"
ran_fail "notes test"
no_fail "boom test"
ran_fail shellcheck
grep -qF "bin/new-tool:1:1: checked" <<< "$out" || fail "--changed $case: shellcheck skipped the untracked script"
! grep -qF "bin/old-tool" <<< "$out" || fail "--changed $case: shellcheck read an unchanged script"
rm "$site/bin/new-tool"

case="a committed pass"
echo 'pass' > "$site/notes.md"
git -C "$site" -c user.name=t -c user.email=t@t commit -q -am pass
changed
[ "$code" = 0 ] || fail "--changed $case: exit $code: $out"
(cd "$site" && bin/check-passed HEAD) && fail "--changed $case: recorded a pass for pre-push"

# A rule over the tree runs whatever changed, no test naming the page.
case="a page no test names"
echo '<a href="/root">root</a>' >> "$site/guide/index.html"
changed
[ "$code" = 1 ] || fail "--changed $case: exit $code, not 1"
ran_fail "root-absolute links"
git -C "$site" checkout -q -- guide/index.html

case="a check name bin/check lacks"
printf '#!/bin/bash\nprintf "file\\tnotes.md\\ncheck\\tno such check\\n"\n' > "$site/bin/check-changed"
changed
ran_fail "bin/check-changed names 'no such check', which bin/check has no check for"
