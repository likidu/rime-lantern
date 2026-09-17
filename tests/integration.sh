#!/usr/bin/env bash
# End-to-end test: deploy Rime-Ice plus rime-lantern into a scratch user
# directory and check candidate comments through librime, headlessly.
#
# Env: RIME_SHARED_DIR (default /usr/share/rime-data), LANTERN_WORK (scratch
# dir, reused across runs to keep the rime-ice clone), RIME_ICE_REF (branch).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
shared="${RIME_SHARED_DIR:-/usr/share/rime-data}"
work="${LANTERN_WORK:-$(mktemp -d)}"
ref="${RIME_ICE_REF:-main}"
probe="$here/tests/harness/rime_probe"
user="$work/user"

[ -x "$probe" ] || cc -O -o "$probe" "$here/tests/harness/rime_probe.c" -lrime
if [ ! -d "$work/rime-ice/.git" ]; then
  git clone --quiet --depth 1 --branch "$ref" https://github.com/iDvel/rime-ice "$work/rime-ice"
fi
rm -rf "$user"; mkdir -p "$user"
cp -r "$work/rime-ice/." "$user/"; rm -rf "$user/.git"
mkdir -p "$user/lua" "$user/lantern"
cp "$here/lua/lantern.lua" "$user/lua/"
cp "$here/lantern/cedict-en.tsv" "$user/lantern/"
cp "$here/examples/rime_ice.custom.yaml" "$here/examples/default.custom.yaml" "$user/"

run() { "$probe" --user "$user" --shared "$shared" --schema rime_ice "$@" 2>/dev/null; }
fail=0
check() { # description, regex, actual
  if grep -qE "$2" <<<"$3"; then echo "ok   $1"; else echo "FAIL $1"; printf '     got: %s\n' "$3"; fail=1; fi
}
t0=$(date +%s)
on_yinhang=$(run --option english_gloss=1 yinhang)   # first run deploys
echo "deploy+probe: $(( $(date +%s) - t0 )) s"
check "银行 is glossed 'bank'"                $'^银行\tbank$'            "$on_yinhang"
check "emoji candidate has no gloss"          $'^🏦\t$'                 "$on_yinhang"
check "corrector hint kept, gloss appended"  $'^给予\tjǐ yǔ · to give$' "$(run --option english_gloss=1 geiyu)"
check "English candidate has no gloss"        $'^hello\t$'              "$(run --option english_gloss=1 hello)"
check "long gloss truncated at word boundary" $'^北京\tBeijing municipality…$' "$(run --option english_gloss=1 beijing)"
check "switch off: no gloss"                  $'^银行\t$'               "$(run yinhang)"
# highlighted mode (default): the gloss follows the highlight
down=$(run --option english_gloss=1 'yinhang{Down}{Down}')
check "highlight moved: first candidate loses gloss" $'^银行\t$'      "$down"
check "highlight moved: emoji still blank"           $'^🏦\t$'        "$down"
check "highlight back: gloss returns with hint kept" $'^给予\tjǐ yǔ · to give$' "$(run --option english_gloss=1 'geiyu{Down}{Up}')"
check "highlight on second candidate"                $'^给\tto$'      "$(run --option english_gloss=1 'geiyu{Down}')"
check "paging: first of page two is glossed"         $'^被\tquilt$'   "$(run --option english_gloss=1 'beijing{Page_Down}')"
# mode: all glosses every candidate
sed 's/mode: highlighted.*/mode: all/' "$here/examples/rime_ice.custom.yaml" > "$user/rime_ice.custom.yaml"
all=$(run --option english_gloss=1 yinhang)
check "mode all: first candidate glossed"            $'^银行\tbank$'  "$all"
check "mode all: later candidate glossed too"        $'^因\tcause$'   "$all"
cp "$here/examples/rime_ice.custom.yaml" "$user/"
check "filter wired into rime_ice"  'lua_filter@\*lantern'  "$(cat "$user/build/rime_ice.schema.yaml")"
check "switch remembered in default" 'english_gloss'         "$(sed -n '/save_options/,/fold_options/p' "$user/build/default.yaml")"
check "hotkey bound"                 'Control\+Shift\+E'     "$(cat "$user/build/rime_ice.schema.yaml")"
check "table loaded once"            'lantern: loaded [0-9]+ rows' "$(cat "$user"/rime.probe.*INFO* 2>/dev/null)"
errors=$(grep -h 'lantern' "$user"/rime.probe.*ERROR* 2>/dev/null || true)
check "no lantern errors in rime log" '^$' "$errors"
exit $fail
