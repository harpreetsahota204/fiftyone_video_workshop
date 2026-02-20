"""
Load the Action100M dataset into FiftyOne.

This script loads the Action100M preview from HuggingFace and creates a
FiftyOne video dataset with temporal annotations from the Tree-of-Captions
pipeline. We store only the GPT-refined Stage 3 outputs — the cross-referenced,
cleaned summaries, actions, and actors — as these are the most reliable
annotations and what the paper uses for training VL-JEPA. Raw Stage 2 captions
(PLM, Llama3) are omitted; GPT fields are only populated for segments ≥ 4s.

Usage (run from the project root):
    python download_scripts/parse_to_fiftyone.py
"""
import os
import fiftyone as fo
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
from datasets import load_dataset

# ── Config ──────────────────────────────────────────────────────────────────

DATASET_PATH = "action100m-preview"
VIDEOS_DIR = "videos"
DATASET_NAME = "action100m"
CLIP_DURATION = 90.0  # seconds
OVERWRITE = True

# ── Step 1: Load from HuggingFace ──────────────────────────────────────────

print("Loading Action100M dataset from HuggingFace...")
hf_dataset = load_dataset(DATASET_PATH)
train_data = hf_dataset["train"]

# ── Step 2: Create the FiftyOne dataset ─────────────────────────────────────

fo_dataset = fo.Dataset(DATASET_NAME, overwrite=OVERWRITE, persistent=True)

# ── Step 3: Parse samples ──────────────────────────────────────────────────

videos_path = Path(VIDEOS_DIR)

# Filter HF dataset to only videos we have on disk
available_uids = {p.stem for p in videos_path.glob("*.mp4")}
train_data = train_data.filter(
    lambda x: x["video_uid"] in available_uids,
    num_proc=os.cpu_count(),
)
print(f"\nFound {len(train_data)} videos on disk (of {len(available_uids)} available)")


def make_temporal_detections(det_list):
    """Wrap a list of TemporalDetection objects into a TemporalDetections
    container — FiftyOne's label type for time-span annotations on video."""
    return fo.TemporalDetections(detections=det_list) if det_list else None


samples = []

for item in tqdm(train_data):
    video_file = videos_path / f"{item['video_uid']}.mp4"

    meta = item["metadata"]
    video_metadata = fo.VideoMetadata.build_for(str(video_file))
    fps = video_metadata.frame_rate

    # ── Parse transcript into text + temporal segments ──

    transcript_text = ""
    transcript_segments = []

    if meta.get("transcript"):
        entries = []
        for t in meta["transcript"]:
            try:
                time, text = float(t["time"]), t["text"]
                if time <= CLIP_DURATION:
                    entries.append((time, text))
            except (ValueError, KeyError):
                continue

        transcript_text = " ".join(text for _, text in entries)

        for i, (time, text) in enumerate(entries):
            end = entries[i + 1][0] if i + 1 < len(entries) else min(time + 3.0, CLIP_DURATION)
            if time < end and time < CLIP_DURATION:
                transcript_segments.append(
                    fo.TemporalDetection(label=text, support=[int(time * fps) + 1, int(end * fps) + 1])
                )

    # ── Parse annotation nodes ──
    #
    # Each node in the tree has a tier:
    #   - "root"  (level 0): full video, global context
    #   - "mid"   (intermediate levels): multi-frame segments
    #   - "leaf"  (deepest level): single keyframe moments

    nodes = item["nodes"]
    max_level = max((n["level"] for n in nodes), default=0)

    # GPT-refined annotations (Stage 3 of the Tree-of-Captions pipeline).
    # These are the cross-referenced, cleaned outputs — the raw PLM/Llama3
    # captions from Stage 2 are intentionally omitted since the GPT fields
    # are strictly more reliable. Only populated for segments ≥ 4 seconds.
    gpt_summary_brief = []
    gpt_summary_detailed = []
    gpt_action_brief = []
    gpt_action_detailed = []
    gpt_action_actor = []

    for node in nodes:
        start, end = node["start"], min(node["end"], CLIP_DURATION)
        if start >= CLIP_DURATION or start >= end:
            continue

        level = node["level"]
        tier = "root" if level == 0 else ("leaf" if level == max_level else "mid")

        # Shared attributes — tree topology + tier for hierarchy-aware browsing
        attrs = dict(
            node_id=node["node_id"],
            parent_id=node.get("parent_id"),
            level=level,
            tier=tier,
        )

        def td(label):
            return fo.TemporalDetection(
                label=label,
                support=[int(start * fps) + 1, int(end * fps) + 1],
                **attrs,
            )

        # Stage 3 — GPT-refined annotations (only for segments ≥ 4s)
        gpt = node.get("gpt") or {}
        summary = gpt.get("summary", {})
        action = gpt.get("action", {})

        if summary.get("brief"):
            gpt_summary_brief.append(td(summary["brief"]))
        if summary.get("detailed"):
            gpt_summary_detailed.append(td(summary["detailed"]))

        # ~3.23% of segments have action="N/A" (intros, ads, non-action content)
        if action.get("brief") and action["brief"] != "N/A":
            gpt_action_brief.append(td(action["brief"]))
        if action.get("detailed") and action["detailed"] != "N/A":
            gpt_action_detailed.append(td(action["detailed"]))
        if action.get("actor"):
            gpt_action_actor.append(td(action["actor"]))

    # ── Build the FiftyOne sample ──

    sample = fo.Sample(
        filepath=str(video_file),
        metadata=video_metadata,
        # Video metadata
        title=meta.get("title"),
        description=meta.get("description"),
        full_video_url=f"https://www.youtube.com/watch?v={item['video_uid']}",
        upload_date=datetime.strptime(meta["upload_date"], "%Y%m%d"),
        view_count=meta.get("view_count"),
        like_count=meta.get("like_count"),
        full_video_duration=meta.get("duration"),
        transcript=transcript_text,
        tree_depth=max_level,
        # GPT-refined temporal annotations
        gpt_summary_brief=make_temporal_detections(gpt_summary_brief),
        gpt_summary_detailed=make_temporal_detections(gpt_summary_detailed),
        gpt_action_brief=make_temporal_detections(gpt_action_brief),
        gpt_action_detailed=make_temporal_detections(gpt_action_detailed),
        gpt_action_actor=make_temporal_detections(gpt_action_actor),
        # Transcript
        transcript_segments=make_temporal_detections(transcript_segments),
    )
    samples.append(sample)

fo_dataset.add_samples(samples)

fo_dataset.add_dynamic_sample_fields()

# ── Done! ───────────────────────────────────────────────────────────────────

print(f"\n✅ Dataset created: {len(fo_dataset)} samples")
print(fo_dataset)