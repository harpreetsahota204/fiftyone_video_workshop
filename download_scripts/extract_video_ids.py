#!/usr/bin/env python3
"""Extract unique video_uid values from the action100m-preview parquet files."""

import glob
import pandas as pd

parquet_files = sorted(glob.glob("action100m-preview/data/part-*.parquet"))
print(f"Found {len(parquet_files)} parquet files")

all_ids = set()
for f in parquet_files:
    df = pd.read_parquet(f, columns=["video_uid"])
    all_ids.update(df["video_uid"].unique())
    print(f"  {f}: {len(df)} rows, running unique total: {len(all_ids)}")

# Write unique IDs to file (one per line)
output_path = "video_ids.txt"
with open(output_path, "w") as fh:
    for vid in sorted(all_ids):
        fh.write(vid + "\n")

print(f"\nWrote {len(all_ids)} unique video IDs to {output_path}")
