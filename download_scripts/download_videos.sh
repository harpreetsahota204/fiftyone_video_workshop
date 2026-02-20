#!/usr/bin/env bash
#
# Download YouTube videos from video_ids.txt using yt-dlp.
# Only downloads videos that actually exist (skips unavailable ones).
#
# Usage:
#   1. First generate video_ids.txt:  python extract_video_ids.py
#   2. Then run this script:          bash download_videos.sh
#
# Options (environment variables):
#   JOBS=N        - number of parallel downloads (default: 4)
#   VIDEO_IDS     - path to video IDs file (default: video_ids.txt)
#   OUTPUT_DIR    - output directory (default: videos)
#   MAX_HEIGHT=N  - max video height in pixels (default: 480)
#   MAX_DURATION=N- keep only the first N seconds (default: 90)
#   MAX_VIDEOS=N  - stop after downloading N videos (default: unlimited)
#   COOKIES       - path to a Netscape cookies.txt file (default: none)
#   COOKIES_FROM  - browser name to extract cookies from (e.g. chrome, firefox)

set -euo pipefail

VIDEO_IDS="${VIDEO_IDS:-video_ids.txt}"
OUTPUT_DIR="${OUTPUT_DIR:-videos}"
JOBS="${JOBS:-4}"
MAX_HEIGHT="${MAX_HEIGHT:-480}"
MAX_DURATION="${MAX_DURATION:-90}"
MAX_VIDEOS="${MAX_VIDEOS:-0}"  # 0 = unlimited
COOKIES="${COOKIES:-}"
COOKIES_FROM="${COOKIES_FROM:-}"
LOG_DIR="${OUTPUT_DIR}/logs"

if [[ ! -f "$VIDEO_IDS" ]]; then
    echo "ERROR: $VIDEO_IDS not found. Run 'python extract_video_ids.py' first."
    exit 1
fi

# Check that yt-dlp is installed
if ! command -v yt-dlp &>/dev/null; then
    echo "ERROR: yt-dlp is not installed. Install with: pip install yt-dlp"
    exit 1
fi

# Check that ffmpeg/ffprobe are installed (needed for codec detection & re-encoding)
if ! command -v ffmpeg &>/dev/null || ! command -v ffprobe &>/dev/null; then
    echo "ERROR: ffmpeg/ffprobe not found. Install with: sudo apt install ffmpeg"
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

TOTAL=$(wc -l < "$VIDEO_IDS")
echo "============================================"
echo " action100m video downloader"
echo "============================================"
echo " Video IDs file : $VIDEO_IDS"
echo " Total IDs      : $TOTAL"
echo " Output dir     : $OUTPUT_DIR"
echo " Max quality    : ${MAX_HEIGHT}p"
echo " Max duration   : ${MAX_DURATION}s"
echo " Max videos     : $( [[ "$MAX_VIDEOS" -gt 0 ]] && echo "$MAX_VIDEOS" || echo "unlimited" )"
echo " Cookies        : ${COOKIES:-${COOKIES_FROM:-(none)}}"
echo " Parallel jobs  : $JOBS"
echo "============================================"
echo ""

# Track progress
DOWNLOADED=0
SKIPPED=0
FAILED=0
ALREADY=0
COUNT=0

download_video() {
    local video_id="$1"
    local url="https://www.youtube.com/watch?v=${video_id}"
    local outfile="${OUTPUT_DIR}/%(id)s.%(ext)s"
    local logfile="${LOG_DIR}/${video_id}.log"

    # Skip if already downloaded (check for any file starting with the video ID)
    if ls "${OUTPUT_DIR}/${video_id}".* &>/dev/null 2>&1; then
        echo "[SKIP] ${video_id} - already downloaded"
        return 2
    fi

    # Build cookie args
    local cookie_args=()
    if [[ -n "$COOKIES" ]]; then
        cookie_args+=(--cookies "$COOKIES")
    elif [[ -n "$COOKIES_FROM" ]]; then
        cookie_args+=(--cookies-from-browser "$COOKIES_FROM")
    fi

    # Step 1: Download (clip to first MAX_DURATION seconds, cap resolution)
    if yt-dlp \
        "${cookie_args[@]}" \
        --format "bestvideo[height<=${MAX_HEIGHT}]+bestaudio/best[height<=${MAX_HEIGHT}]/best" \
        --merge-output-format mp4 \
        --download-sections "*0-${MAX_DURATION}" \
        --force-keyframes-at-cuts \
        --no-overwrites \
        --socket-timeout 30 \
        --retries 3 \
        --output "$outfile" \
        "$url" \
        > "$logfile" 2>&1; then

        # Step 2: Ensure FiftyOne compatibility:
        #   - H.264 (libx264) video codec
        #   - AAC audio codec
        #   - yuv420p pixel format
        #   - Even width and height
        local downloaded
        downloaded=$(ls "${OUTPUT_DIR}/${video_id}".* 2>/dev/null | head -1)
        if [[ -n "$downloaded" ]]; then
            local vcodec acodec pixfmt width height
            vcodec=$(ffprobe -v error -select_streams v:0 \
                     -show_entries stream=codec_name -of csv=p=0 \
                     "$downloaded" 2>/dev/null || echo "unknown")
            acodec=$(ffprobe -v error -select_streams a:0 \
                     -show_entries stream=codec_name -of csv=p=0 \
                     "$downloaded" 2>/dev/null || echo "unknown")
            pixfmt=$(ffprobe -v error -select_streams v:0 \
                     -show_entries stream=pix_fmt -of csv=p=0 \
                     "$downloaded" 2>/dev/null || echo "unknown")
            width=$(ffprobe -v error -select_streams v:0 \
                    -show_entries stream=width -of csv=p=0 \
                    "$downloaded" 2>/dev/null || echo "0")
            height=$(ffprobe -v error -select_streams v:0 \
                     -show_entries stream=height -of csv=p=0 \
                     "$downloaded" 2>/dev/null || echo "0")

            local needs_reencode=false
            local reasons=""

            [[ "$vcodec" != "h264" ]]  && needs_reencode=true && reasons+="vcodec=${vcodec} "
            [[ "$acodec" != "aac" ]]   && needs_reencode=true && reasons+="acodec=${acodec} "
            [[ "$pixfmt" != "yuv420p" ]] && needs_reencode=true && reasons+="pix=${pixfmt} "
            (( width  % 2 != 0 ))      && needs_reencode=true && reasons+="odd_w=${width} "
            (( height % 2 != 0 ))      && needs_reencode=true && reasons+="odd_h=${height} "

            if $needs_reencode; then
                local tmpfile="${downloaded}.tmp.mp4"
                # -vf pad: round up to even dimensions if needed
                if ffmpeg -y -i "$downloaded" \
                    -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
                    -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
                    -c:a aac -b:a 128k \
                    -movflags +faststart \
                    "$tmpfile" >> "$logfile" 2>&1; then
                    mv "$tmpfile" "${OUTPUT_DIR}/${video_id}.mp4"
                    [[ "$downloaded" != "${OUTPUT_DIR}/${video_id}.mp4" ]] && rm -f "$downloaded"
                    echo "[OK]   ${video_id} (re-encoded: ${reasons})"
                else
                    rm -f "$tmpfile"
                    echo "[OK]   ${video_id} (re-encode failed, keeping original)"
                fi
            else
                # Already compliant — just ensure faststart moov atom
                local tmpfile="${downloaded}.tmp.mp4"
                if ffmpeg -y -i "$downloaded" -c copy -movflags +faststart \
                    "$tmpfile" >> "$logfile" 2>&1; then
                    mv "$tmpfile" "${OUTPUT_DIR}/${video_id}.mp4"
                    [[ "$downloaded" != "${OUTPUT_DIR}/${video_id}.mp4" ]] && rm -f "$downloaded"
                fi
                echo "[OK]   ${video_id} (already compliant)"
            fi
        else
            echo "[OK]   ${video_id}"
        fi
        return 0
    else
        # Check if the video is unavailable vs. a transient error
        if grep -qiE "video unavailable|private video|removed|copyright|account terminated|not available" "$logfile" 2>/dev/null; then
            echo "[GONE] ${video_id} - video unavailable"
        else
            echo "[FAIL] ${video_id} - see ${logfile}"
        fi
        return 1
    fi
}

export -f download_video
export OUTPUT_DIR LOG_DIR MAX_HEIGHT MAX_DURATION MAX_VIDEOS COOKIES COOKIES_FROM

# ---------- parallel vs sequential ----------
if command -v parallel &>/dev/null && [[ "$JOBS" -gt 1 ]]; then
    echo "Using GNU parallel with $JOBS jobs..."
    echo ""
    if [[ "$MAX_VIDEOS" -gt 0 ]]; then
        head -n "$MAX_VIDEOS" "$VIDEO_IDS" | parallel --bar --jobs "$JOBS" download_video
    else
        parallel --bar --jobs "$JOBS" download_video :::: "$VIDEO_IDS"
    fi
    echo ""
    echo "Done. Check ${LOG_DIR}/ for per-video logs."
else
    if [[ "$JOBS" -gt 1 ]] && ! command -v parallel &>/dev/null; then
        echo "NOTE: GNU parallel not found. Falling back to sequential downloads."
        echo "      Install with: sudo apt install parallel  (for parallel downloads)"
        echo ""
    fi

    while IFS= read -r video_id || [[ -n "$video_id" ]]; do
        # Skip empty lines and comments
        [[ -z "$video_id" || "$video_id" == \#* ]] && continue

        COUNT=$((COUNT + 1))

        # Stop if we've hit the max
        if [[ "$MAX_VIDEOS" -gt 0 && "$DOWNLOADED" -ge "$MAX_VIDEOS" ]]; then
            echo ""
            echo "Reached MAX_VIDEOS=$MAX_VIDEOS downloads. Stopping."
            break
        fi

        printf "[%d/%d] " "$COUNT" "$TOTAL"
        download_video "$video_id"
        rc=$?

        case $rc in
            0) DOWNLOADED=$((DOWNLOADED + 1)) ;;
            1) FAILED=$((FAILED + 1)) ;;
            2) ALREADY=$((ALREADY + 1)) ;;
        esac
    done < "$VIDEO_IDS"

    echo ""
    echo "============================================"
    echo " Summary"
    echo "============================================"
    echo " Downloaded : $DOWNLOADED"
    echo " Already    : $ALREADY"
    echo " Failed     : $FAILED"
    echo " Total      : $COUNT"
    echo "============================================"
fi
