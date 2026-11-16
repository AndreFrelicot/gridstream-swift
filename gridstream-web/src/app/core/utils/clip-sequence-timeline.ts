import { ClipSequence, ClipSequenceSegment, TimelinePosition } from '../models/clip-sequence.model';
import { TimeRangeInfo } from '../models/time-range.model';
import { VideoItem } from '../models/video.model';

const SEGMENT_COLORS = [
  '#38bdf8',
  '#f97316',
  '#22c55e',
  '#eab308',
  '#a855f7',
  '#ec4899',
  '#14b8a6',
  '#f43f5e',
];

interface BuildClipSequenceOptions {
  title: string;
  sourceLabel: string;
  videos: VideoItem[];
  rangesByFileId: Record<string, TimeRangeInfo[]>;
}

export function buildClipSequence(options: BuildClipSequenceOptions): ClipSequence {
  const segments: ClipSequenceSegment[] = [];
  let virtualCursor = 0;

  for (const video of options.videos) {
    const ranges = [...(options.rangesByFileId[video.fileId] ?? [])].sort(
      (a, b) => a.startTime - b.startTime,
    );

    for (const range of ranges) {
      const normalized = normalizeRange(video, range);
      if (!normalized) continue;

      const duration = normalized.endTime - normalized.startTime;
      const segment: ClipSequenceSegment = {
        id: range.id,
        rangeId: range.id,
        video,
        videoFileId: video.fileId,
        startTime: normalized.startTime,
        endTime: normalized.endTime,
        duration,
        virtualStart: virtualCursor,
        virtualEnd: virtualCursor + duration,
        label: range.label,
        color: getVideoSegmentColor(video.fileId),
        thumbnailTime: normalized.startTime + duration / 2,
      };

      segments.push(segment);
      virtualCursor = segment.virtualEnd;
    }
  }

  return {
    title: options.title,
    sourceLabel: options.sourceLabel,
    segments,
    duration: virtualCursor,
  };
}

export function mapVirtualTimeToSegment(
  sequence: ClipSequence,
  virtualTime: number,
): TimelinePosition | null {
  const segmentIndex = findSegmentIndexAtVirtualTime(sequence, virtualTime);
  if (segmentIndex < 0) return null;

  const segment = sequence.segments[segmentIndex];
  const clampedVirtualTime = clamp(virtualTime, 0, sequence.duration);
  const sourceTime = clamp(
    segment.startTime + (clampedVirtualTime - segment.virtualStart),
    segment.startTime,
    segment.endTime,
  );

  return {
    segment,
    segmentIndex,
    virtualTime: clampedVirtualTime,
    sourceTime,
  };
}

export function findSegmentAtVirtualTime(
  sequence: ClipSequence,
  virtualTime: number,
): ClipSequenceSegment | null {
  const index = findSegmentIndexAtVirtualTime(sequence, virtualTime);
  return index >= 0 ? sequence.segments[index] : null;
}

export function findSegmentIndexAtVirtualTime(sequence: ClipSequence, virtualTime: number): number {
  if (sequence.segments.length === 0 || sequence.duration <= 0) return -1;

  const clampedVirtualTime = clamp(virtualTime, 0, sequence.duration);
  if (clampedVirtualTime >= sequence.duration) {
    return sequence.segments.length - 1;
  }

  return sequence.segments.findIndex(
    (segment) =>
      clampedVirtualTime >= segment.virtualStart && clampedVirtualTime < segment.virtualEnd,
  );
}

export function getVideoSegmentColor(fileId: string): string {
  let hash = 0;
  for (let i = 0; i < fileId.length; i += 1) {
    hash = (hash * 31 + fileId.charCodeAt(i)) >>> 0;
  }
  return SEGMENT_COLORS[hash % SEGMENT_COLORS.length];
}

function normalizeRange(
  video: VideoItem,
  range: TimeRangeInfo,
): { startTime: number; endTime: number } | null {
  if (
    !Number.isFinite(video.duration) ||
    video.duration <= 0 ||
    !Number.isFinite(range.startTime) ||
    !Number.isFinite(range.endTime) ||
    range.startTime < 0 ||
    range.endTime <= range.startTime ||
    range.startTime >= video.duration
  ) {
    return null;
  }

  const startTime = range.startTime;
  const endTime = Math.min(range.endTime, video.duration);
  if (endTime <= startTime) return null;

  return { startTime, endTime };
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
