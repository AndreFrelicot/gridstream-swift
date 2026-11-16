import { captureDownloadName } from './captures.component';

describe('captureDownloadName', () => {
  it('replaces the video extension and encodes the timestamp', () => {
    expect(captureDownloadName({ filename: 'match.final.mp4', timestamp: 65.7 })).toBe(
      'match.final_1m05s.jpg',
    );
  });

  it('falls back to "capture" without a filename', () => {
    expect(captureDownloadName({ filename: null, timestamp: 3 })).toBe('capture_0m03s.jpg');
  });
});
