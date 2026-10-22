#!/usr/bin/env bash
# Publishes language indexes as GitHub release assets of this repository.
#
# Usage: upload.sh IDX_DIR OUT_DIR TAG
#   IDX_DIR  holds <code>.idx files and manifest.json
#            ({languages: [{code, name, entries, bytes, sha256, url}]})
#   OUT_DIR  receives <code>.idx.gz and the published manifest.json
#   TAG      release tag, e.g. data-2026-10-22
#
# Every index listed in the manifest is gzipped (skipped when the .gz is
# newer than the .idx), the manifest is rewritten with `gzBytes` and with
# `url` relative to the manifest URL (../../download/<tag>/<code>.idx.gz),
# then everything is uploaded with `gh release upload`. A release holds at
# most 1000 assets, so larger sets are split over TAG-2, TAG-3, ...; those
# are created first and TAG, which holds the manifest, last and marked
# latest. Assets already uploaded with the same size are skipped, so a
# failed run can be repeated.
set -euo pipefail

REPO=d33mobile/wiktionary-lookup-data
ASSETS_PER_RELEASE=900
idx_dir=${1:?usage: upload.sh IDX_DIR OUT_DIR TAG}
out_dir=${2:?usage: upload.sh IDX_DIR OUT_DIR TAG}
tag=${3:?usage: upload.sh IDX_DIR OUT_DIR TAG}
mkdir -p "$out_dir"

gzip_cmd=(gzip -9 -n -c)
if command -v pigz >/dev/null; then gzip_cmd=(pigz -9 -n -c); fi

# Gzip, then write the published manifest and one "tag<TAB>file" line per asset.
python3 -I - "$idx_dir" "$out_dir" "$tag" "$ASSETS_PER_RELEASE" "${gzip_cmd[@]}" <<'PY'
import json, os, pathlib, subprocess, sys
idx_dir, out_dir, tag, per_release = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], int(sys.argv[4])
gzip_cmd = sys.argv[5:]
manifest = json.loads((idx_dir / "manifest.json").read_text())
plan = []
for i, lang in enumerate(manifest["languages"]):
    code = lang["code"]
    src = idx_dir / f"{code}.idx"
    dst = out_dir / f"{code}.idx.gz"
    if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
        tmp = dst.with_suffix(".gz.tmp")
        with open(tmp, "wb") as f:
            subprocess.run([*gzip_cmd, str(src)], stdout=f, check=True)
        os.replace(tmp, dst)
    part = i // per_release
    release = tag if part == 0 else f"{tag}-{part + 1}"
    lang["bytes"] = src.stat().st_size
    lang["gzBytes"] = dst.stat().st_size
    lang["url"] = f"../../download/{release}/{dst.name}"
    plan.append(f"{release}\t{dst}")
(out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n")
plan.append(f"{tag}\t{out_dir / 'manifest.json'}")
(out_dir / "upload-plan.tsv").write_text("\n".join(plan) + "\n")
print(f"{len(manifest['languages'])} languages, {sum(l['gzBytes'] for l in manifest['languages'])} bytes gzipped")
PY

# Extra parts first (sorted descending so TAG is created last and is the latest).
mapfile -t releases < <(cut -f1 "$out_dir/upload-plan.tsv" | sort -u | sort -r -V)
for release in "${releases[@]}"; do
    if ! gh release view "$release" -R "$REPO" >/dev/null 2>&1; then
        latest=--latest=false
        if [ "$release" = "$tag" ]; then latest=--latest; fi
        gh release create "$release" -R "$REPO" "$latest" --title "Dictionary data $release" \
            --notes "Language indexes for Wiktionary Lookup. Data from English Wiktionary via kaikki.org, CC BY-SA 4.0."
    fi
    declare -A have=()
    while IFS=$'\t' read -r name size; do have[$name]=$size; done < <(
        gh release view "$release" -R "$REPO" --json assets --jq '.assets[] | "\(.name)\t\(.size)"')
    todo=()
    while IFS=$'\t' read -r rel file; do
        [ "$rel" = "$release" ] || continue
        name=$(basename "$file")
        # The manifest always changes with a new upload; other assets are skipped when unchanged.
        if [ "$name" != manifest.json ] && [ "${have[$name]:-}" = "$(stat -c %s "$file")" ]; then continue; fi
        todo+=("$file")
    done < "$out_dir/upload-plan.tsv"
    unset have
    echo "$release: ${#todo[@]} assets to upload"
    # gh uploads the files of one call one after another; batches keep a failure cheap to repeat.
    for ((i = 0; i < ${#todo[@]}; i += 20)); do
        gh release upload "$release" -R "$REPO" --clobber "${todo[@]:i:20}"
    done
done
echo "manifest: https://github.com/$REPO/releases/latest/download/manifest.json"
