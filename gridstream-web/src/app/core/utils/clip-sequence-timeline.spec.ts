import { describe, expect, it } from 'vitest';
import {
  buildClipSequence,
  findSegmentAtVirtualTime,
  getVideoSegmentColor,
  mapVirtualTimeToSegment,
} from './clip-sequence-timeline';
import { TimeRangeInfo } from '../models/time-range.model';
import { VideoItem } from '../models/video.model';

describe('clip-sequence-timeline', () => {
  it('builds virtual offsets in video order and range start order', () => {
    const videos = [makeVideo('a', 100), makeVideo('b', 100)];
    const sequence = buildClipSequence({
      title: 'Selections',
      sourceLabel: 'Library',
      videos,
      rangesByFileId: {
        a: [makeRange('a-2', 'a', 20, 25), makeRange('a-1', 'a', 5, 8)],
        b: [makeRange('b-1', 'b', 1, 4)],
      },
    });

    expect(sequence.duration).toBe(11);
    expect(sequence.segments.map((segment) => segment.id)).toEqual(['a-1', 'a-2', 'b-1']);
    expect(sequence.segments.map((segment) => segment.virtualStart)).toEqual([0, 3, 8]);
    expect(sequence.segments.map((segment) => segment.virtualEnd)).toEqual([3, 8, 11]);
  });

  it('drops invalid ranges and clamps ranges to video duration', () => {
    const video = makeVideo('a', 10);
    const sequence = buildClipSequence({
      title: 'Selections',
      sourceLabel: 'Library',
      videos: [video],
      rangesByFileId: {
        a: [
          makeRange('negative', 'a', -1, 2),
          makeRange('zero', 'a', 2, 2),
          makeRange('past-end', 'a', 11, 12),
          makeRange('clamped', 'a', 8, 12),
        ],
      },
    });

    expect(sequence.segments).toHaveLength(1);
    expect(sequence.segments[0].id).toBe('clamped');
    expect(sequence.segments[0].endTime).toBe(10);
    expect(sequence.segments[0].duration).toBe(2);
    expect(sequence.duration).toBe(2);
  });

  it('maps virtual times to source times across segment boundaries', () => {
    const videos = [makeVideo('a', 100), makeVideo('b', 100)];
    const sequence = buildClipSequence({
      title: 'Selections',
      sourceLabel: 'Library',
      videos,
      rangesByFileId: {
        a: [makeRange('a-1', 'a', 10, 15)],
        b: [makeRange('b-1', 'b', 30, 34)],
      },
    });

    expect(mapVirtualTimeToSegment(sequence, 2)?.sourceTime).toBe(12);
    expect(mapVirtualTimeToSegment(sequence, 5)?.segment.id).toBe('b-1');
    expect(mapVirtualTimeToSegment(sequence, 5)?.sourceTime).toBe(30);
    expect(mapVirtualTimeToSegment(sequence, 8)?.sourceTime).toBe(33);
  });

  it('keeps final virtual time on the final segment end', () => {
    const sequence = buildClipSequence({
      title: 'Selections',
      sourceLabel: 'Library',
      videos: [makeVideo('a', 100)],
      rangesByFileId: {
        a: [makeRange('a-1', 'a', 10, 12)],
      },
    });

    expect(findSegmentAtVirtualTime(sequence, sequence.duration)?.id).toBe('a-1');
    expect(mapVirtualTimeToSegment(sequence, sequence.duration)?.sourceTime).toBe(12);
  });

  it('assigns stable colors per video id', () => {
    expect(getVideoSegmentColor('same-file')).toBe(getVideoSegmentColor('same-file'));
  });
});

function makeVideo(fileId: string, duration: number): VideoItem {
  return {
    id: fileId,
    fileId,
    filename: `${fileId}.mp4`,
    relativePath: `${fileId}.mp4`,
    sourceDirectoryId: 'source',
    duration,
    width: 1920,
    height: 1080,
    codec: 'h264',
    fileSize: 1000,
    lastModified: '2026-01-01T00:00:00Z',
    rating: 0,
    playCount: 0,
    totalViewTime: 0,
    annotationCount: 0,
  };
}

function makeRange(
  id: string,
  videoFileId: string,
  startTime: number,
  endTime: number,
): TimeRangeInfo {
  return {
    id,
    videoFileId,
    startTime,
    endTime,
    label: null,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  };
}
