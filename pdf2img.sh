#!/usr/bin/env bash
# Convert every PDF under a folder (recursively) into JPEG image(s), each
# capped at a max file size (default: under 2MB, for VFS Global's upload
# limit). Multi-page / oversized PDFs are split into multiple JPEGs named
# "<name> - N-of-M.jpg".
#
# Usage: ./pdf2img.sh [root-folder]     (default: ~/Desktop/olga)
#
# Requires: pdftoppm, convert (poppler-utils + imagemagick).
# On NixOS: nix-shell -p poppler-utils imagemagick --run './pdf2img.sh <folder>'

set -uo pipefail

ROOT="${1:-$HOME/Desktop/olga}"
DPI=200
QUALITY=90
MAX_BYTES=1900000   # buffer under the 2MB backend limit

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

log() { printf '%s\n' "$*" >&2; }

render_page() {
  # render_page <pdf> <page_no> <dpi> <out_prefix>
  local pdf="$1" page="$2" dpi="$3" out="$4"
  pdftoppm -jpeg -q -r "$dpi" -f "$page" -l "$page" "$pdf" "$out" >/dev/null 2>&1
}

page_num_of() {
  # extracts the numeric page index from a "page-<N>.jpg" path
  basename "$1" | sed -E 's/^page-([0-9]+)\.jpg$/\1/'
}

build_output() {
  # build_output <out> <file1> [file2 ...]   (uses current $Q)
  local out="$1"; shift
  if [ "$#" -eq 1 ]; then
    convert "$1" -quality "$Q" "$out" 2>/dev/null
  else
    convert "$@" -append -quality "$Q" "$out" 2>/dev/null
  fi
}

make_group_output() {
  # make_group_output <out> <pdf> <workdir> <file1> [file2 ...]
  # writes $out from the given page-jpeg files, shrinking (quality, then DPI
  # by re-rendering straight from the PDF) until it's under MAX_BYTES.
  local out="$1" pdf="$2" workdir="$3"; shift 3
  local files=("$@")

  Q=$QUALITY
  build_output "$out" "${files[@]}"
  local sz
  sz=$(stat -c%s "$out")

  while [ "$sz" -gt "$MAX_BYTES" ] && [ "$Q" -gt 35 ]; do
    Q=$((Q-15))
    build_output "$out" "${files[@]}"
    sz=$(stat -c%s "$out")
  done

  if [ "$sz" -gt "$MAX_BYTES" ]; then
    # quality alone wasn't enough: re-render the same pages at lower DPI
    local -a lowfiles=()
    for lowdpi in 150 120 100 80 60; do
      lowfiles=()
      local ok=1
      for f in "${files[@]}"; do
        local pn
        pn=$(page_num_of "$f")
        render_page "$pdf" "$pn" "$lowdpi" "$workdir/low${lowdpi}_${pn}"
        local lf
        lf=$(ls "$workdir/low${lowdpi}_${pn}"*.jpg 2>/dev/null | head -1)
        if [ -z "$lf" ] || [ ! -f "$lf" ]; then ok=0; break; fi
        lowfiles+=("$lf")
      done
      [ "$ok" -eq 1 ] || continue
      Q=75
      build_output "$out" "${lowfiles[@]}"
      sz=$(stat -c%s "$out")
      Q=50
      while [ "$sz" -gt "$MAX_BYTES" ] && [ "$Q" -gt 30 ]; do
        build_output "$out" "${lowfiles[@]}"
        sz=$(stat -c%s "$out")
        Q=$((Q-10))
      done
      [ "$sz" -le "$MAX_BYTES" ] && break
    done
  fi

  if [ "$sz" -gt "$MAX_BYTES" ]; then
    log "  WARNING: $(basename "$out") still ${sz} bytes after best-effort shrink"
  fi
}

process_pdf() {
  local pdf="$1"
  local dir base
  dir="$(dirname "$pdf")"
  base="$(basename "$pdf")"
  base="${base%.*}"

  local workdir="$TMPROOT/$(echo "$pdf" | md5sum | cut -d' ' -f1)"
  mkdir -p "$workdir"

  pdftoppm -jpeg -q -r "$DPI" -jpegopt quality="$QUALITY" "$pdf" "$workdir/page" 2>/dev/null
  if [ $? -ne 0 ]; then
    log "FAILED to render: $pdf"
    return
  fi

  mapfile -t pages < <(ls "$workdir"/page-*.jpg 2>/dev/null | sort -V)
  local n=${#pages[@]}
  if [ "$n" -eq 0 ]; then
    log "NO PAGES rendered: $pdf"
    return
  fi

  # greedy grouping (based on each page's initial quality-$QUALITY size;
  # final group files are shrunk to fit MAX_BYTES after creation, see below)
  local groups=()
  local current=()
  local current_size=0
  for p in "${pages[@]}"; do
    sz=$(stat -c%s "$p")
    if [ "${#current[@]}" -gt 0 ] && [ $(( current_size + sz )) -gt "$MAX_BYTES" ]; then
      groups+=("$(IFS='|'; echo "${current[*]}")")
      current=()
      current_size=0
    fi
    current+=("$p")
    current_size=$(( current_size + sz ))
  done
  if [ "${#current[@]}" -gt 0 ]; then
    groups+=("$(IFS='|'; echo "${current[*]}")")
  fi

  local total=${#groups[@]}
  local idx=1
  for g in "${groups[@]}"; do
    IFS='|' read -ra filesArr <<< "$g"
    local suffix=""
    if [ "$total" -gt 1 ]; then
      suffix=" - ${idx}-of-${total}"
    fi
    local out="$dir/${base}${suffix}.jpg"
    make_group_output "$out" "$pdf" "$workdir" "${filesArr[@]}"
    local outsz
    outsz=$(stat -c%s "$out")
    log "  -> $(basename "$out")  (${outsz} bytes, ${#filesArr[@]} page(s))"
    idx=$((idx+1))
  done

  rm -rf "$workdir"
}

log "Scanning $ROOT for PDFs..."
while IFS= read -r -d '' pdf; do
  log "Processing: $pdf"
  process_pdf "$pdf"
done < <(find "$ROOT" -iname '*.pdf' -print0 | sort -z)

log "Done."
