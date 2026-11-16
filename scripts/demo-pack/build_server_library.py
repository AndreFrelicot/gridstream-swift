#!/usr/bin/env python3
"""Builds a library for the macOS server from the iPad demo pack.

    build_server_library.py PACK OUT

PACK is a built demo pack (build/demo-pack/v1, see make-demo-pack.sh). OUT
receives the same library as the real server stores it:

    Demo/<filename>          the clips, under their catalog names
    Data/gridstream.sqlite   the server database: videos, thumbnails, ratings,
                             tags, lists, annotations and time ranges of the
                             pack, with OUT/Demo as its only source folder

To serve it, choose OUT/Data as the data directory in the server's Storage
settings (without moving the current database) and restart the server.

The pack names a clip after the SHA-256 of its content; the server uses its
own file id (FileHasher: xxHash64 of three chunks and the size), so every
reference to a clip is rewritten with that id. Rows are written as the scanner
would leave them, which makes the first scan find nothing to change.

OUT must not hold a database yet: nothing is overwritten.
"""

import json
import os
import shutil
import sqlite3
import struct
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

NAMESPACE = uuid.UUID("6f1c2d4e-8a3b-4c5d-9e7f-0a1b2c3d4e5f")

# The schema DatabaseManager.runMigrations leaves in a new database. A server
# with later migrations applies them on launch: MIGRATIONS lists what is here.
MIGRATIONS = [
    "v1_create_video_files", "v2_create_tags", "v3_add_ratings", "v4_create_thumbnails",
    "v5_create_app_metadata", "v6_add_play_count_tracking", "v7_create_smart_lists",
    "v8_create_simple_lists", "v9_create_simple_list_videos", "v10_create_scrub_videos",
    "v11_create_scrub_queue", "v12_create_scrub_frames", "v13_create_source_directories",
    "v14_create_time_ranges", "v15_add_last_played_at", "v16_create_annotations",
    "v17_add_annotation_count", "v18_add_scrub_frame_format", "v19_add_filter_indexes",
    "v20_create_frame_captures", "v21_add_annotation_text", "v22_create_annotation_text_search",
    "v23_add_last_played_at_partial_index", "v24_add_scrub_frame_count",
    "v25_drop_redundant_scrub_indexes", "v26_add_scrub_failure_tracking", "v27_add_missing_since",
    "v28_normalize_smart_list_criteria", "v29_normalize_simple_list_sort_order",
]
SCHEMA = """
CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
CREATE TABLE "video_files" ("id" TEXT PRIMARY KEY, "file_id" TEXT NOT NULL UNIQUE, "path" TEXT NOT NULL, "source_directory_id" TEXT NOT NULL, "filename" TEXT NOT NULL, "file_size" INTEGER NOT NULL, "duration" DOUBLE NOT NULL, "width" INTEGER NOT NULL, "height" INTEGER NOT NULL, "codec" TEXT NOT NULL, "last_modified" DOUBLE NOT NULL, "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL, "rating" INTEGER NOT NULL DEFAULT 0, "play_count" INTEGER NOT NULL DEFAULT 0, "total_view_time" INTEGER NOT NULL DEFAULT 0, "last_played_at" DOUBLE, "annotation_count" INTEGER DEFAULT 0, "scrub_frame_count" INTEGER DEFAULT 0, "scrub_attempt_count" INTEGER DEFAULT 0, "scrub_failed" INTEGER DEFAULT 0, "scrub_last_error" TEXT, "scrub_last_attempt_at" DOUBLE, "missing_since" DOUBLE);
CREATE TABLE "tags" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL UNIQUE, "color" TEXT NOT NULL, "description" TEXT, "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL, "rating_enabled" INTEGER NOT NULL DEFAULT 0);
CREATE TABLE "video_tags" ("id" TEXT PRIMARY KEY, "video_file_id" TEXT NOT NULL REFERENCES "video_files"("file_id") ON DELETE CASCADE, "tag_id" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE, "created_at" DOUBLE NOT NULL, "rating" INTEGER NOT NULL DEFAULT 0, UNIQUE ("video_file_id", "tag_id"));
CREATE TABLE "thumbnails" ("id" TEXT PRIMARY KEY, "file_id" TEXT NOT NULL UNIQUE, "image_data" BLOB NOT NULL, "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL);
CREATE TABLE "app_metadata" ("key" TEXT PRIMARY KEY, "value" TEXT NOT NULL, "updated_at" DOUBLE NOT NULL);
CREATE TABLE "smart_lists" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL UNIQUE, "criteria" TEXT NOT NULL, "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL);
CREATE TABLE "simple_lists" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL UNIQUE, "sort_order" TEXT NOT NULL DEFAULT 'filename', "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL);
CREATE TABLE "simple_list_videos" ("id" TEXT PRIMARY KEY, "simple_list_id" TEXT NOT NULL, "video_file_id" TEXT NOT NULL, "position" INTEGER NOT NULL DEFAULT 0, "added_at" DOUBLE NOT NULL);
CREATE TABLE "scrub_frames" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "file_id" TEXT NOT NULL, "timestamp" DOUBLE NOT NULL, "frame_data" BLOB NOT NULL, "quality" INTEGER DEFAULT 85, "created_at" DOUBLE NOT NULL, "format" TEXT NOT NULL DEFAULT 'heic', UNIQUE ("file_id", "timestamp"));
CREATE TABLE "source_directories" ("id" TEXT PRIMARY KEY, "path" TEXT NOT NULL, "is_enabled" BOOLEAN NOT NULL DEFAULT 1, "last_scanned" DOUBLE, "bookmark_data" BLOB, "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL);
CREATE TABLE "time_ranges" ("id" TEXT PRIMARY KEY, "video_file_id" TEXT NOT NULL, "start_time" DOUBLE NOT NULL, "end_time" DOUBLE NOT NULL, "label" TEXT, "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL);
CREATE TABLE "video_annotations" ("id" TEXT PRIMARY KEY, "video_file_id" TEXT NOT NULL, "frame_time" DOUBLE NOT NULL, "frame_rate" DOUBLE NOT NULL, "strokes_json" TEXT NOT NULL, "created_at" DOUBLE NOT NULL, "updated_at" DOUBLE NOT NULL, "text" TEXT, UNIQUE ("video_file_id", "frame_time"));
CREATE TABLE "frame_captures" ("id" TEXT PRIMARY KEY, "file_id" TEXT NOT NULL, "timestamp" DOUBLE NOT NULL, "image_data" BLOB NOT NULL, "width" INTEGER NOT NULL, "height" INTEGER NOT NULL, "file_size" INTEGER NOT NULL, "created_at" DOUBLE NOT NULL);
CREATE INDEX "idx_video_files_file_id" ON "video_files"("file_id");
CREATE INDEX "idx_video_files_source_directory_id" ON "video_files"("source_directory_id");
CREATE INDEX "idx_tags_name" ON "tags"("name");
CREATE INDEX "idx_video_tags_video_file_id" ON "video_tags"("video_file_id");
CREATE INDEX "idx_video_tags_tag_id" ON "video_tags"("tag_id");
CREATE INDEX "idx_video_files_rating" ON "video_files"("rating");
CREATE INDEX "idx_thumbnails_file_id" ON "thumbnails"("file_id");
CREATE INDEX "idx_video_files_play_count" ON "video_files"("play_count");
CREATE INDEX "idx_smart_lists_name" ON "smart_lists"("name");
CREATE INDEX "idx_simple_lists_name" ON "simple_lists"("name");
CREATE INDEX "idx_simple_list_videos_list_id" ON "simple_list_videos"("simple_list_id");
CREATE INDEX "idx_simple_list_videos_video_id" ON "simple_list_videos"("video_file_id");
CREATE UNIQUE INDEX "idx_simple_list_videos_unique" ON "simple_list_videos"("simple_list_id", "video_file_id");
CREATE UNIQUE INDEX "idx_source_directories_path" ON "source_directories"("path");
CREATE INDEX "idx_time_ranges_video_file_id" ON "time_ranges"("video_file_id");
CREATE INDEX "idx_video_files_last_played_at" ON "video_files"("last_played_at");
CREATE INDEX "idx_video_annotations_video_file_id" ON "video_annotations"("video_file_id");
CREATE INDEX idx_video_files_filename ON video_files(filename);
CREATE INDEX idx_video_files_file_size ON video_files(file_size);
CREATE INDEX idx_video_files_created_at ON video_files(created_at);
CREATE INDEX idx_video_files_last_modified ON video_files(last_modified);
CREATE INDEX idx_video_files_annotation_count ON video_files(annotation_count);
CREATE INDEX "idx_frame_captures_file_id" ON "frame_captures"("file_id");
CREATE INDEX "idx_frame_captures_created_at" ON "frame_captures"("created_at");
CREATE VIRTUAL TABLE video_annotation_text_fts USING fts5(
    annotation_id UNINDEXED,
    video_file_id UNINDEXED,
    text,
    tokenize = 'unicode61'
);
CREATE TRIGGER video_annotations_text_fts_insert
AFTER INSERT ON video_annotations
WHEN NEW.text IS NOT NULL AND TRIM(NEW.text) <> ''
BEGIN
    INSERT INTO video_annotation_text_fts(rowid, annotation_id, video_file_id, text)
    VALUES (NEW.rowid, NEW.id, NEW.video_file_id, NEW.text);
END;
CREATE TRIGGER video_annotations_text_fts_update
AFTER UPDATE OF video_file_id, text ON video_annotations
BEGIN
    DELETE FROM video_annotation_text_fts WHERE rowid = OLD.rowid;
    INSERT INTO video_annotation_text_fts(rowid, annotation_id, video_file_id, text)
    SELECT NEW.rowid, NEW.id, NEW.video_file_id, NEW.text
    WHERE NEW.text IS NOT NULL AND TRIM(NEW.text) <> '';
END;
CREATE TRIGGER video_annotations_text_fts_delete
AFTER DELETE ON video_annotations
BEGIN
    DELETE FROM video_annotation_text_fts WHERE rowid = OLD.rowid;
END;
CREATE INDEX idx_video_files_last_played_at_not_null
ON video_files(last_played_at)
WHERE last_played_at IS NOT NULL;
CREATE INDEX "idx_video_files_scrub_failed" ON "video_files"("scrub_failed");
CREATE INDEX "idx_video_files_missing_since" ON "video_files"("missing_since");
"""

# ThumbnailGenerator: the frame fits in 320 x 180.
THUMBNAIL_BOX = "320:180"
# MetadataExtractor.codecName for the codecs ffprobe may report here.
CODECS = {"h264": "h264", "hevc": "hevc", "mpeg4": "mpeg4"}

MASK = (1 << 64) - 1
PRIME1, PRIME2, PRIME3 = 11400714785074694791, 14029467366897019727, 1609587929392839161
PRIME4, PRIME5 = 9650029242287828579, 2870177450012600261


def rotl(value, bits):
    return ((value << bits) | (value >> (64 - bits))) & MASK


def xxh64_round(acc, lane):
    return (rotl((acc + lane * PRIME2) & MASK, 31) * PRIME1) & MASK


def xxh64(data):
    """xxHash64 with seed 0."""
    length = len(data)
    position = 0
    if length >= 32:
        v1, v2, v3, v4 = (PRIME1 + PRIME2) & MASK, PRIME2, 0, (-PRIME1) & MASK
        while position <= length - 32:
            a, b, c, d = struct.unpack_from("<4Q", data, position)
            v1, v2, v3, v4 = xxh64_round(v1, a), xxh64_round(v2, b), xxh64_round(v3, c), xxh64_round(v4, d)
            position += 32
        digest = (rotl(v1, 1) + rotl(v2, 7) + rotl(v3, 12) + rotl(v4, 18)) & MASK
        for lane in (v1, v2, v3, v4):
            digest = ((digest ^ xxh64_round(0, lane)) * PRIME1 + PRIME4) & MASK
    else:
        digest = PRIME5
    digest = (digest + length) & MASK
    while position + 8 <= length:
        digest ^= xxh64_round(0, struct.unpack_from("<Q", data, position)[0])
        digest = (rotl(digest, 27) * PRIME1 + PRIME4) & MASK
        position += 8
    if position + 4 <= length:
        digest ^= (struct.unpack_from("<I", data, position)[0] * PRIME1) & MASK
        digest = (rotl(digest, 23) * PRIME2 + PRIME3) & MASK
        position += 4
    while position < length:
        digest ^= (data[position] * PRIME5) & MASK
        digest = (rotl(digest, 11) * PRIME1) & MASK
        position += 1
    digest = ((digest ^ (digest >> 33)) * PRIME2) & MASK
    digest = ((digest ^ (digest >> 29)) * PRIME3) & MASK
    return digest ^ (digest >> 32)


def server_file_id(path):
    """FileHasher.computeFileId: first, middle and last 64 KB, then the size."""
    chunk = 65_536
    size = path.stat().st_size
    if size < 3 * chunk:
        sys.exit(f"{path.name} is too small for the server to hash")
    hashes = []
    with open(path, "rb") as handle:
        for offset in (0, size // 2 - chunk // 2, size - chunk):
            handle.seek(offset)
            hashes.append(xxh64(handle.read(chunk)))
    return f"{xxh64(struct.pack('>3Qq', *hashes, size)):016x}"


def probe(path):
    """Duration, size and codec as MetadataExtractor reads them."""
    output = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,codec_name,sample_aspect_ratio:format=duration",
         "-of", "json", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout
    data = json.loads(output)
    stream = data["streams"][0]
    codec = stream["codec_name"]
    if codec not in CODECS:
        sys.exit(f"{path.name}: unexpected codec {codec}")
    # AVFoundation's naturalSize applies the pixel aspect ratio; the extractor truncates it.
    numerator, denominator = map(int, stream.get("sample_aspect_ratio", "1:1").split(":"))
    width = stream["width"] * numerator // denominator if numerator and denominator else stream["width"]
    return {
        "duration": float(data["format"]["duration"]),
        "width": width,
        "height": stream["height"],
        "codec": CODECS[codec],
    }


def server_thumbnail(source):
    return subprocess.run(
        ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(source),
         "-vf", f"scale={THUMBNAIL_BOX}:force_original_aspect_ratio=decrease",
         "-frames:v", "1", "-q:v", "3", "-f", "image2pipe", "-c:v", "mjpeg", "-"],
        check=True, capture_output=True,
    ).stdout


def blob(identifier):
    """GRDB stores a UUID as its 16 bytes."""
    return uuid.UUID(identifier).bytes


def derived(*parts):
    return uuid.uuid5(NAMESPACE, "/".join(parts)).bytes


def seconds(iso):
    return datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    pack, out = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
    seed = json.loads((pack / "seed.json").read_text())
    videos_directory = out / seed["sourceDirectoryName"]
    database_path = out / "Data" / "gridstream.sqlite"
    if database_path.exists():
        sys.exit(f"{database_path} already exists: remove {out} to rebuild it")
    videos_directory.mkdir(parents=True, exist_ok=True)
    database_path.parent.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(database_path)
    db.executescript(SCHEMA)
    db.executemany("INSERT INTO grdb_migrations VALUES (?)", [(name,) for name in MIGRATIONS])

    source_directory_id = blob(seed["sourceDirectoryId"])
    created = min(seconds(video["createdAt"]) for video in seed["videos"])
    db.execute(
        "INSERT INTO source_directories (id, path, is_enabled, created_at, updated_at) VALUES (?, ?, 1, ?, ?)",
        (source_directory_id, str(videos_directory), created, created),
    )

    annotation_counts = {}
    for annotation in seed["annotations"]:
        annotation_counts[annotation["videoFileId"]] = annotation_counts.get(annotation["videoFileId"], 0) + 1

    file_ids = {}
    for video in seed["videos"]:
        pack_id = video["fileId"]
        target = videos_directory / video["filename"]
        shutil.copyfile(pack / "clips" / f"{pack_id}.mp4", target)
        modified = seconds(video["lastModified"])
        os.utime(target, (modified, modified))
        file_id = file_ids[pack_id] = server_file_id(target)
        info = probe(target)
        added = seconds(video["createdAt"])
        db.execute(
            """INSERT INTO video_files (id, file_id, path, source_directory_id, filename, file_size,
                   duration, width, height, codec, last_modified, created_at, updated_at, rating,
                   play_count, total_view_time, last_played_at, annotation_count)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (blob(video["id"]), file_id, str(target), source_directory_id, video["filename"],
             target.stat().st_size, info["duration"], info["width"], info["height"], info["codec"],
             target.stat().st_mtime, added, added, video["rating"], video["playCount"],
             video["totalViewTime"],
             seconds(video["lastPlayedAt"]) if "lastPlayedAt" in video else None,
             annotation_counts.get(pack_id, 0)),
        )
        db.execute(
            "INSERT INTO thumbnails (id, file_id, image_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (derived("thumbnail", video["id"]), file_id,
             server_thumbnail(pack / "thumbnails" / f"{pack_id}.jpg"), added, added),
        )

    for tag in seed["tags"]:
        db.execute(
            "INSERT INTO tags (id, name, color, description, created_at, updated_at, rating_enabled) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (blob(tag["id"]), tag["name"], tag["color"], tag.get("description"),
             seconds(tag["createdAt"]), seconds(tag["updatedAt"]), int(tag["ratingEnabled"])),
        )
    tag_dates = {tag["id"]: seconds(tag["createdAt"]) for tag in seed["tags"]}
    for link in seed["videoTags"]:
        db.execute(
            "INSERT INTO video_tags (id, video_file_id, tag_id, created_at, rating) VALUES (?, ?, ?, ?, ?)",
            (derived("video-tag", link["fileId"], link["tagId"]), file_ids[link["fileId"]],
             blob(link["tagId"]), tag_dates[link["tagId"]], link.get("rating", 0)),
        )

    for item in seed["smartLists"]:
        db.execute(
            "INSERT INTO smart_lists (id, name, criteria, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (blob(item["id"]), item["name"], item["criteria"],
             seconds(item["createdAt"]), seconds(item["updatedAt"])),
        )
    for item in seed["simpleLists"]:
        db.execute(
            "INSERT INTO simple_lists (id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            (blob(item["id"]), item["name"], item["sortOrder"],
             seconds(item["createdAt"]), seconds(item["updatedAt"])),
        )
        for position, pack_id in enumerate(item["videoIds"]):
            db.execute(
                "INSERT INTO simple_list_videos (id, simple_list_id, video_file_id, position, added_at) VALUES (?, ?, ?, ?, ?)",
                (derived("simple-list-video", item["id"], pack_id), blob(item["id"]),
                 file_ids[pack_id], position, seconds(item["createdAt"])),
            )

    for item in seed["annotations"]:
        db.execute(
            """INSERT INTO video_annotations (id, video_file_id, frame_time, frame_rate, strokes_json,
                   created_at, updated_at, text) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (blob(item["id"]), file_ids[item["videoFileId"]], item["frameTime"], item["frameRate"],
             item["strokesJSON"], seconds(item["createdAt"]), seconds(item["updatedAt"]), item.get("text")),
        )
    for item in seed["timeRanges"]:
        db.execute(
            "INSERT INTO time_ranges (id, video_file_id, start_time, end_time, label, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (blob(item["id"]), file_ids[item["videoFileId"]], item["startTime"], item["endTime"],
             item.get("label"), seconds(item["createdAt"]), seconds(item["updatedAt"])),
        )
    if seed["captures"]:
        sys.exit("The pack holds captures, which this script does not write yet")

    latest = max(seconds(item["updatedAt"]) for item in seed["annotations"] + seed["timeRanges"] + seed["tags"])
    db.execute(
        "INSERT INTO app_metadata (key, value, updated_at) VALUES ('catalog_version', ?, ?)",
        (str(int(latest * 1000)), latest),
    )
    db.commit()
    db.close()
    print(f"Library ready in {out}: {len(file_ids)} clips in {videos_directory.name}/, database in Data/")


if __name__ == "__main__":
    main()
