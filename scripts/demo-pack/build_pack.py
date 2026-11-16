#!/usr/bin/env python3
"""Builds the iPad demo pack from cut clips and a curated catalog.

    build_pack.py SOURCES CATALOG WORK OUT

SOURCES is scripts/demo-pack/sources.json (films, clips, credits), CATALOG is
scripts/demo-pack/catalog.json (names, tags, lists, annotations, time
ranges, keyed by clip id) and WORK holds the cut clips (<clip id>.mp4).

OUT receives the layout DemoPack expects:
    clips/<fileId>.mp4, thumbnails/<fileId>.jpg, seed.json, CREDITS.md,
    manifest.json (written last: its presence marks a complete pack).

Everything is deterministic: ids are UUIDv5 of stable names and dates are
fixed, so rebuilding unchanged inputs yields the same pack.
"""

import hashlib
import json
import math
import shutil
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

NAMESPACE = uuid.UUID("6f1c2d4e-8a3b-4c5d-9e7f-0a1b2c3d4e5f")
BASE_DATE = datetime(2026, 10, 1, 9, 0, 0, tzinfo=timezone.utc)
TAG_COLORS = {
    "#EF4444", "#F97316", "#F59E0B", "#22C55E", "#10B981",
    "#06B6D4", "#3B82F6", "#8B5CF6", "#A855F7", "#EC4899",
}
THUMBNAIL_WIDTH = 480


def stable_id(*parts):
    return str(uuid.uuid5(NAMESPACE, "/".join(parts))).upper()


def iso(date):
    return date.strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def probe(path):
    output = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,codec_tag_string,r_frame_rate:format=duration",
         "-of", "json", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout
    data = json.loads(output)
    stream = data["streams"][0]
    numerator, denominator = stream["r_frame_rate"].split("/")
    return {
        "width": int(stream["width"]),
        "height": int(stream["height"]),
        "codec": stream["codec_tag_string"],
        "frameRate": float(numerator) / float(denominator),
        "duration": round(float(data["format"]["duration"]), 3),
    }


def make_thumbnail(clip, at, target):
    subprocess.run(
        ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
         "-ss", str(at), "-i", str(clip), "-frames:v", "1",
         "-vf", f"scale={THUMBNAIL_WIDTH}:-2", "-q:v", "4", str(target)],
        check=True,
    )


def condition(index, list_key, raw, tag_ids, simple_list_ids, smart_list_ids):
    """One criteria condition, with catalog keys resolved to ids."""
    raw = dict(raw)
    operator = raw.pop("op", "AND")
    kind = raw["type"]
    if kind == "tagsInclude":
        ratings = []
        for key, bounds in raw.get("tagRatings", {}).items():
            rating = {"tagId": tag_ids[key]}
            if "min" in bounds:
                rating["minRating"] = bounds["min"]
            if "max" in bounds:
                rating["maxRating"] = bounds["max"]
            ratings.append(rating)
        criteria = {"type": kind, "tagIds": [tag_ids[key] for key in raw["tags"]], "tagRatings": ratings}
    elif kind == "tagsExclude":
        criteria = {"type": kind, "tagIds": [tag_ids[key] for key in raw["tags"]]}
    elif kind == "simpleListInclude":
        criteria = {"type": kind, "simpleListId": simple_list_ids[raw["list"]]}
    elif kind == "smartListInclude":
        criteria = {"type": kind, "smartListId": smart_list_ids[raw["list"]]}
    else:
        criteria = raw
    return {
        "criteriaType": criteria,
        "id": stable_id("condition", list_key, str(index)),
        "logicOperator": operator,
    }


def stroke_points(stroke, info):
    """A stroke's points; `circle: [cx, cy, r]` draws a circle (r in heights)."""
    if "circle" not in stroke:
        return stroke["points"]
    cx, cy, radius = stroke["circle"]
    aspect = info["height"] / info["width"]
    steps = 48
    return [
        (round(cx + radius * aspect * math.cos(2 * math.pi * i / steps), 4),
         round(cy + radius * math.sin(2 * math.pi * i / steps), 4))
        for i in range(steps + 1)
    ]


def canonical_json(value):
    # Matches JSONEncoder.gridStreamCanonical: sorted keys, no spaces.
    text = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return text.replace("/", "\\/")


def main():
    sources_path, catalog_path, work, out = map(Path, sys.argv[1:5])
    sources = json.loads(sources_path.read_text())
    catalog = json.loads(catalog_path.read_text())

    if out.exists():
        shutil.rmtree(out)
    (out / "clips").mkdir(parents=True)
    (out / "thumbnails").mkdir()

    tags = catalog["tags"]
    tag_ids = {tag["key"]: stable_id("tag", tag["key"]) for tag in tags}
    simple_list_ids = {item["key"]: stable_id("simple-list", item["key"]) for item in catalog["simpleLists"]}
    smart_list_ids = {item["key"]: stable_id("smart-list", item["key"]) for item in catalog["smartLists"]}
    for tag in tags:
        if tag["color"] not in TAG_COLORS:
            sys.exit(f"Tag {tag['key']}: {tag['color']} is not in TagColorPalette")

    file_ids = {}
    infos = {}
    videos = []
    video_tags = []
    for index, clip in enumerate(sources["clips"]):
        clip_id = clip["id"]
        entry = catalog["clips"][clip_id]
        source = work / f"{clip_id}.mp4"
        file_id = sha256(source)[:16]
        file_ids[clip_id] = file_id
        info = probe(source)
        infos[clip_id] = info

        shutil.copyfile(source, out / "clips" / f"{file_id}.mp4")
        make_thumbnail(source, entry.get("thumbnailAt", round(info["duration"] / 3, 2)),
                       out / "thumbnails" / f"{file_id}.jpg")

        added = BASE_DATE + timedelta(days=index, hours=index % 5)
        played = entry.get("playCount", 0)
        videos.append({
            "id": stable_id("video", clip_id),
            "fileId": file_id,
            "filename": entry["filename"],
            "duration": info["duration"],
            "width": info["width"],
            "height": info["height"],
            "codec": info["codec"],
            "fileSize": source.stat().st_size,
            "lastModified": iso(added - timedelta(days=30)),
            "createdAt": iso(added),
            "rating": entry.get("rating", 0),
            "playCount": played,
            "totalViewTime": int(played * info["duration"] * 0.8),
            **({"lastPlayedAt": iso(added + timedelta(days=20))} if played else {}),
        })
        for tag in entry.get("tags", []):
            key, rating = (tag, None) if isinstance(tag, str) else (tag["tag"], tag.get("rating"))
            link = {"fileId": file_id, "tagId": tag_ids[key]}
            if rating is not None:
                link["rating"] = rating
            video_tags.append(link)

    seed_tags = [{
        "id": tag_ids[tag["key"]],
        "name": tag["name"],
        "color": tag["color"],
        **({"description": tag["description"]} if tag.get("description") else {}),
        "ratingEnabled": tag.get("ratingEnabled", False),
        "createdAt": iso(BASE_DATE),
        "updatedAt": iso(BASE_DATE),
    } for tag in tags]

    simple_lists = [{
        "id": simple_list_ids[item["key"]],
        "name": item["name"],
        "sortOrder": item.get("sortOrder", "filename"),
        "videoIds": [file_ids[clip] for clip in item["clips"]],
        "createdAt": iso(BASE_DATE),
        "updatedAt": iso(BASE_DATE),
    } for item in catalog["simpleLists"]]

    smart_lists = [{
        "id": smart_list_ids[item["key"]],
        "name": item["name"],
        "criteria": canonical_json({"conditions": [
            condition(index, item["key"], raw, tag_ids, simple_list_ids, smart_list_ids)
            for index, raw in enumerate(item["conditions"])
        ]}),
        "createdAt": iso(BASE_DATE),
        "updatedAt": iso(BASE_DATE),
    } for item in catalog["smartLists"]]

    annotations = []
    for index, item in enumerate(catalog["annotations"]):
        info = infos[item["clip"]]
        frame_rate = info["frameRate"]
        frame_time = round(item["time"] * frame_rate) / frame_rate
        strokes = [{
            "color": stroke.get("color", "#EF4444"),
            "width": stroke.get("width", 6),
            "opacity": stroke.get("opacity", 1),
            "points": [{"x": x, "y": y, "pressure": 0.8} for x, y in stroke_points(stroke, info)],
        } for stroke in item.get("strokes", [])]
        annotations.append({
            "id": stable_id("annotation", item["clip"], str(index)),
            "videoFileId": file_ids[item["clip"]],
            "frameTime": round(frame_time, 6),
            "frameRate": frame_rate,
            "strokesJSON": json.dumps(strokes, separators=(",", ":")),
            **({"text": item["text"]} if item.get("text") else {}),
            "createdAt": iso(BASE_DATE + timedelta(days=15)),
            "updatedAt": iso(BASE_DATE + timedelta(days=15)),
        })

    time_ranges = []
    for index, item in enumerate(catalog["timeRanges"]):
        duration = infos[item["clip"]]["duration"]
        if not 0 <= item["start"] < item["end"] <= duration:
            sys.exit(f"Time range {index} on {item['clip']} is outside the clip")
        time_ranges.append({
            "id": stable_id("time-range", item["clip"], str(index)),
            "videoFileId": file_ids[item["clip"]],
            "startTime": item["start"],
            "endTime": item["end"],
            **({"label": item["label"]} if item.get("label") else {}),
            "createdAt": iso(BASE_DATE + timedelta(days=16)),
            "updatedAt": iso(BASE_DATE + timedelta(days=16)),
        })

    seed = {
        "catalogVersion": 1,
        "sourceDirectoryId": stable_id("source-directory", "demo"),
        "sourceDirectoryName": "Demo",
        "videos": videos,
        "tags": seed_tags,
        "videoTags": video_tags,
        "smartLists": smart_lists,
        "simpleLists": simple_lists,
        "annotations": annotations,
        "timeRanges": time_ranges,
        "captures": [],
    }
    (out / "seed.json").write_text(json.dumps(seed, indent=2, sort_keys=True, ensure_ascii=False) + "\n")

    credits = ["# Demo videos", "",
               "The demo clips are excerpts of open movies by the Blender Foundation,",
               "shortened and re-encoded for GridStream. Thank you to their makers.", ""]
    for key, film in sources["films"].items():
        clips = [catalog["clips"][clip["id"]]["filename"] for clip in sources["clips"] if clip["film"] == key]
        credits += [f"## {film['title']}", "", film["credit"], "",
                    f"Licensed under [{film['license']}]({film['licenseUrl']}).", "",
                    "Clips: " + ", ".join(clips) + ".", ""]
    (out / "CREDITS.md").write_text("\n".join(credits))

    files = []
    for path in sorted(out.rglob("*")):
        if path.is_file():
            files.append({"path": path.relative_to(out).as_posix(), "size": path.stat().st_size, "sha256": sha256(path)})
    manifest = {
        "version": 1,
        "clipCount": len(videos),
        "totalSize": sum(item["size"] for item in files),
        "files": files,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Pack ready in {out}: {len(videos)} clips, {manifest['totalSize'] / 1_000_000:.1f} MB")


if __name__ == "__main__":
    main()
