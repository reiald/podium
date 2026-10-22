#!/usr/bin/env bash
# Extract every frame of a screen clip to numbered PNGs for frame-by-frame feel measurement.
# Usage: scripts/extract-frames.sh <clip> <outdir>
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <clip> <outdir>" >&2
    exit 2
fi

clip="$1"
outdir="$2"

for tool in ffmpeg ffprobe; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: $tool not found. Install it with: brew install ffmpeg" >&2
        exit 1
    fi
done

if [ ! -f "$clip" ]; then
    echo "error: clip not found: $clip" >&2
    exit 1
fi

if [ -d "$outdir" ] && [ -n "$(ls -A "$outdir")" ]; then
    echo "error: refusing to write into non-empty directory: $outdir" >&2
    exit 1
fi

mkdir -p "$outdir"

fps="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
    -of default=noprint_wrappers=1:nokey=1 "$clip")"
frames="$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets \
    -of default=noprint_wrappers=1:nokey=1 "$clip")"

echo "clip:   $clip"
echo "fps:    $fps (r_frame_rate)"
echo "frames: $frames"
echo "output: $outdir/%04d.png"

# -fps_mode passthrough is the modern spelling of the old `-vsync 0`
# (this ffmpeg no longer accepts -vsync).
ffmpeg -hide_banner -loglevel error -i "$clip" -fps_mode passthrough "$outdir/%04d.png"
