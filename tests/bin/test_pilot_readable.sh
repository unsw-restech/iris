#!/bin/bash
# bin/pilot-readable.py over a scratch tree, with a fake `getfacl` on PATH
# that answers each path's ACL from a file in $acls named after it, or
# other::r-x where there is none. Prints each failed case and nothing on
# success, so bin/check can run it.
#
#   tests/bin/test_pilot_readable.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fake="$scratch/fake" acls="$scratch/acls" tree="$scratch/tree"
mkdir -p "$fake" "$acls" "$tree/sub"

cat > "$fake/getfacl" <<EOF
#!/bin/bash
for arg in "\$@"; do
    case "\$arg" in -p) ;; -R) recurse=1 ;; *) paths+=("\$arg") ;; esac
done
[ -n "\$recurse" ] && mapfile -t paths < <(find "\${paths[@]}")
for p in "\${paths[@]}"; do
    echo "# file: \$p"
    acl="$acls/\${p//\//_}"
    if [ -e "\$acl" ]; then cat "\$acl"; else echo "other::r-x"; fi
    echo
done
EOF
chmod +x "$fake/getfacl"

# acl <path> <line>...: the fake's ACL for <path>.
acl() { local p="$1"; shift; printf '%s\n' "$@" > "$acls/${p//\//_}"; }

touch "$tree/plain" "$tree/hidden" "$tree/named" "$tree/masked" "$tree/tool"
chmod 755 "$tree/tool"
acl "$tree/hidden" "other::---"
acl "$tree/named" "group:katana_ai_ro:r--" "other::---"
acl "$tree/masked" "group:katana_ai_ro:rw-	#effective:-w-" "mask::-w-" "other::r--"
acl "$tree/tool" "other::r--"
acl "$tree/sub" "group:katana_ai_ro:r--" "other::r-x"
acl "$scratch" "other::---"

out="$(PATH="$fake:$PATH" bin/pilot-readable.py "$tree")"
rc=$?
[ "$rc" = 1 ] || echo "pilot-readable: exit $rc, expected 1"
want="needs --x: $scratch
needs r--: $tree/hidden
needs r--: $tree/masked
needs r-x: $tree/sub
needs r-x: $tree/tool"
[ "$out" = "$want" ] || { echo "pilot-readable: listed"; echo "$out" | sed 's/^/  /'; echo "  expected"; echo "$want" | sed 's/^/  /'; }

rm "$acls"/*
out="$(PATH="$fake:$PATH" bin/pilot-readable.py "$tree")"
rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || { echo "pilot-readable on a readable tree: exit $rc"; echo "$out" | sed 's/^/  /'; }
