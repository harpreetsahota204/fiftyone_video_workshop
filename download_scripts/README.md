# Action100M Video Download

Scripts to download YouTube videos referenced in the [facebook/action100m-preview](https://huggingface.co/datasets/facebook/action100m-preview) dataset.

## Prerequisites

```bash
pip install huggingface_hub pandas pyarrow yt-dlp
conda install -c conda-forge ffmpeg nodejs
```

- **ffmpeg / ffprobe** -- needed for codec detection and re-encoding to H.264
- **nodejs** -- needed by yt-dlp as a JavaScript runtime for YouTube extraction

Optionally, for parallel downloads:

```bash
sudo apt install parallel
```

## Step 1: Download the dataset from Hugging Face

```python
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="facebook/action100m-preview",
    repo_type="dataset",
    local_dir="./action100m-preview"
)
```

This downloads the parquet files containing video metadata (including `video_uid`) to `action100m-preview/`.

## Step 2: Extract video IDs

```bash
python download_scripts/extract_video_ids.py
```

Reads all parquet files, deduplicates the `video_uid` column, and writes one YouTube video ID per line to `video_ids.txt`.

## Step 3: Download videos

```bash
bash download_scripts/download_videos.sh
```

This downloads each video into a `videos/` directory. By default, videos are:

- Capped at **480p** resolution
- Trimmed to the **first 90 seconds**
- Ensured to be **H.264 (libx264) / AAC** with **yuv420p** pixel format and **even dimensions** (for FiftyOne compatibility)
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

The script is resumable. Re-running it will skip any videos that already have a downloaded `.mp4` file. To retry videos that previously failed, clear their log files first:

```bash
cd videos/logs
for log in *.log; do
    vid="${log%.log}"
    ls "../${vid}".* &>/dev/null 2>&1 || rm "$log"
done
cd ../..
bash download_scripts/download_videos.sh
```
