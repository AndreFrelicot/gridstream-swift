import { VideoItem } from './video.model';

export interface BlockedVideo {
  video: VideoItem;
  path: string;
  attemptCount: number;
  lastError: string | null;
  lastAttemptAt: number | null;
  frameCount: number;
  expectedFrames: number;
}
