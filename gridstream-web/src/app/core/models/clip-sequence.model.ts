import { VideoItem } from './video.model';

export interface ClipSequenceSegment {
  id: string;
  rangeId: string;
  video: VideoItem;
  videoFileId: string;
  startTime: number;
  endTime: number;
  duration: number;
  virtualStart: number;
  virtualEnd: number;
  label?: string | null;
  color: string;
  thumbnailTime: number;
}

export interface ClipSequence {
  title: string;
  sourceLabel: string;
  segments: ClipSequenceSegment[];
  duration: number;
}

export interface TimelinePosition {
  segment: ClipSequenceSegment;
  segmentIndex: number;
  virtualTime: number;
  sourceTime: number;
}
