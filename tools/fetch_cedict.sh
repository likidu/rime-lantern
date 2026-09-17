#!/usr/bin/env bash
# Download the current CC-CEDICT release into .scratch/ and print its header.
# The release is identified by the "#! date=" line; record it in lantern/cedict-en.tsv.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$here/.scratch/cedict}"
mkdir -p "$out"
url="https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
curl -fsSL "$url" -o "$out/cedict.txt.gz"
gunzip -kf "$out/cedict.txt.gz"
sha256sum "$out/cedict.txt" | tee "$out/cedict.txt.sha256"
grep '^#!' "$out/cedict.txt"
