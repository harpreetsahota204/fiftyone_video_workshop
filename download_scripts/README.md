# Action100M — Local Dataset Setup

Scripts to download YouTube videos from the [facebook/action100m-preview](https://huggingface.co/datasets/facebook/action100m-preview) dataset and build a FiftyOne dataset from scratch.

> **Run all commands from the project root**, not from inside `download_scripts/`.

---

## Quick Start

```bash
# 1. Extract video IDs (also downloads the dataset parquet files from HuggingFace)
python download_scripts/extract_video_ids.py

# 2. Download videos
bash download_scripts/download_videos.sh

# 3. Parse into a FiftyOne dataset
python download_scripts/parse_to_fiftyone.py
```

---

## Prerequisites

```bash
pip install huggingface_hub pandas pyarrow datasets fiftyone yt-dlp tqdm
conda install -c conda-forge ffmpeg nodejs
```

- **ffmpeg / ffprobe** — needed for codec detection and re-encoding to H.264
- **nodejs** — needed by yt-dlp as a JavaScript runtime for YouTube extraction

For parallel downloads (optional but recommended):

```bash
sudo apt install parallel
```

---

## Step 1: Extract Video IDs

```bash
python download_scripts/extract_video_ids.py
```

This script:
1. Downloads the dataset parquet files from HuggingFace (`facebook/action100m-preview`) into `action100m-preview/` — skipped automatically if already present
2. Reads all parquet files, deduplicates the `video_uid` column
3. Writes one YouTube video ID per line to `video_ids.txt`

---

## Step 2: Download Videos

```bash
bash download_scripts/download_videos.sh
```

Downloads each video into a `videos/` directory. By default, videos are:

- Capped at **480p** resolution
- Trimmed to the **first 90 seconds**
- Re-encoded to **H.264 (libx264) / AAC** with **yuv420p** pixel format and **even dimensions** for FiftyOne compatibility
- Saved as `.mp4` with the `faststart` flag for instant playback

### Options

All options are passed as environment variables:

| Variable | Default | Description |
|---|---|---|
| `JOBS` | `4` | Number of parallel downloads |
| `MAX_VIDEOS` | unlimited | Stop after downloading N videos |
| `MAX_HEIGHT` | `480` | Max video height in pixels |
| `MAX_DURATION` | `90` | Keep only the first N seconds |
| `COOKIES` | (none) | Path to a Netscape `cookies.txt` file |
| `COOKIES_FROM` | (none) | Browser to extract cookies from (e.g. `chrome`, `firefox`) |
| `VIDEO_IDS` | `video_ids.txt` | Path to the video IDs file |
| `OUTPUT_DIR` | `videos` | Output directory for downloaded videos |

### Examples

```bash
# Download 100 videos with 8 parallel jobs
MAX_VIDEOS=100 JOBS=8 bash download_scripts/download_videos.sh

# Lower quality (360p) and shorter clips (60s)
MAX_HEIGHT=360 MAX_DURATION=60 bash download_scripts/download_videos.sh

# Use browser cookies to avoid YouTube bot detection
COOKIES_FROM=chrome JOBS=8 bash download_scripts/download_videos.sh

# Use an exported cookies file (for headless/remote machines)
COOKIES=cookies.txt JOBS=8 bash download_scripts/download_videos.sh
```

### Resuming

The script is resumable. Re-running it skips any video that already has a downloaded `.mp4` file. To retry videos that previously failed, clear their log files first:

```bash
cd videos/logs
for log in *.log; do
    vid="${log%.log}"
    ls "../${vid}".* &>/dev/null 2>&1 || rm "$log"
done
cd ../..
bash download_scripts/download_videos.sh
```

---

## Step 3: Parse into a FiftyOne Dataset

```bash
python download_scripts/parse_to_fiftyone.py
```

This script:
1. Loads the parquet annotations from `action100m-preview/`
2. Filters to only the video IDs you have on disk in `videos/`
3. Builds a persistent FiftyOne video dataset named `action100m` with all Tree-of-Captions annotations stored as `TemporalDetections`

The resulting dataset has the following fields on each sample:

**Video metadata:** `title`, `description`, `full_video_url`, `upload_date`, `view_count`, `like_count`, `full_video_duration`, `transcript`, `tree_depth`

**GPT-refined annotations** (Stage 3 only — most reliable, segments ≥ 4s):
- `gpt_summary_brief` — one-sentence clip caption per segment
- `gpt_summary_detailed` — full play-by-play description per segment
- `gpt_action_brief` — short verb phrase action label
- `gpt_action_detailed` — instruction-style action description
- `gpt_action_actor` — who performs the action

**Transcript:** `transcript_segments` — ASR entries as time-aligned `TemporalDetections`

Each `TemporalDetection` carries `node_id`, `parent_id`, `level`, and `tier` attributes for reconstructing the tree hierarchy.

### Configuration

Edit the constants at the top of `parse_to_fiftyone.py` to change defaults:

```python
DATASET_PATH  = "action100m-preview"  # local path to parquet files
VIDEOS_DIR    = "videos"              # directory containing downloaded .mp4 files
DATASET_NAME  = "action100m"          # FiftyOne dataset name
CLIP_DURATION = 90.0                  # seconds — annotations beyond this are dropped
OVERWRITE     = True                  # overwrite existing FiftyOne dataset
```

---

## Output Structure

After all three steps, your directory should look like:

```
action100m-preview/     ← parquet files from HuggingFace
videos/
  <video_id>.mp4        ← downloaded and re-encoded clips
  logs/
    <video_id>.log      ← per-video yt-dlp logs
video_ids.txt           ← one YouTube ID per line
```

And a persistent FiftyOne dataset named `action100m` accessible via:

```python
import fiftyone as fo
dataset = fo.load_dataset("action100m")
session = fo.launch_app(dataset)
```
